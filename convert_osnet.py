import torch
import sys
import os
import urllib.request

def download_and_patch_osnet():
    local_file = "osnet_def.py"
    if not os.path.exists(local_file):
        print("正在绕过庞大依赖库，直接下载轻量级 OSNet 网络骨架...")
        url = "https://ghproxy.net/https://raw.githubusercontent.com/KaiyangZhou/deep-person-reid/master/torchreid/models/osnet.py"
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req) as response:
                content = response.read().decode('utf-8')
        except Exception as e:
            print(f"下载网络骨架失败: {e}")
            sys.exit(1)
            
        lines = content.split('\n')
        patched_lines = []
        for line in lines:
            if "from torchreid" in line or "from ." in line or "import load_pretrained_weights" in line:
                continue
            if "load_pretrained_weights(" in line:
                patched_lines.append("        pass  # bypassed")
                continue
            patched_lines.append(line)
            
        with open(local_file, "w", encoding='utf-8') as f:
            f.write('\n'.join(patched_lines))
        print(f"纯净版网络骨架已保存为 {local_file}")

def main():
    download_and_patch_osnet()
    
    try:
        from osnet_def import osnet_x1_0
    except Exception as e:
        print(f"导入网络骨架失败: {e}")
        return

    print("正在构建 OSNet 网络结构...")
    model = osnet_x1_0(num_classes=1000, pretrained=False, loss='softmax')

    weight_path = os.path.abspath('models/osnet_x1_0_imagenet.pth')
    if not os.path.exists(weight_path):
        print(f"错误: 找不到文件 {weight_path}")
        return

    print(f"正在加载本地权重: {weight_path}")
    checkpoint = torch.load(weight_path, map_location='cpu')
    
    if isinstance(checkpoint, dict) and 'state_dict' in checkpoint:
        state_dict = checkpoint['state_dict']
    else:
        state_dict = checkpoint
        
    model.load_state_dict(state_dict, strict=False)
    model.eval()

    output_path = os.path.abspath('models/osnet_x1_0.onnx')
    print(f"正在转换并导出为 ONNX 格式 -> {output_path} ...")
    
    dummy_input = torch.randn(1, 3, 256, 128)
    
    torch.onnx.export(
        model, 
        dummy_input, 
        output_path,
        export_params=True,
        opset_version=12,
        do_constant_folding=True,
        input_names=['images'],
        output_names=['features'],
        dynamic_axes={'images': {0: 'batch_size'}, 'features': {0: 'batch_size'}}
    )

    print(f"转换大功告成！文件已保存在 {output_path}")

if __name__ == '__main__':
    main()
