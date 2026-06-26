"""
QA 问答记录管理模块

提供：
1. save_temp_record(): 保存临时处理记录
2. update_record(): 更新问答记录
3. delete_record(): 删除指定问答记录
4. get_user_records(): 获取用户的所有问答记录
"""

import os
import sys
import json
import yaml
import uuid
from datetime import datetime
from typing import Dict, List, Any, Optional
import shutil

# 将父目录添加到导入路径
current_file = os.path.abspath(__file__)
qa_dir = os.path.dirname(current_file)
project_root = os.path.dirname(qa_dir)  # backend 目录
sys.path.append(project_root)

# 项目根目录（backend 的父目录）- 用于存储数据
base_project_root = os.path.dirname(project_root)


class QAManager:
    """管理问答记录的存储和检索"""
    
    def __init__(self, config_path: str):
        """
        初始化 QAManager
        
        Args:
            config_path (str): qa_storage.yaml 配置文件的路径
        """
        self.config_path = config_path
        self.config = self._load_config(config_path)
        self.storage_dir = self._get_storage_dir()
        self.max_records = self.config['storage'].get('max_records_per_user', 100)
        self.backup_dir = self._get_backup_dir()

        os.makedirs(self.storage_dir, exist_ok=True)
        if self.config['storage'].get('enable_backup', True):
            os.makedirs(self.backup_dir, exist_ok=True)
    
    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """加载 YAML 配置文件"""
        if not os.path.exists(config_path):
            raise FileNotFoundError(f"Config file not found: {config_path}")
        with open(config_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    
    def _get_storage_dir(self) -> str:
        """获取存储目录的绝对路径"""
        storage_path = self.config['storage'].get('storage_dir', 'output/qa_records')
        
        # 如果是相对路径，相对于项目根目录（backend 的父目录）
        if not os.path.isabs(storage_path):
            storage_path = os.path.join(base_project_root, storage_path)
        
        return os.path.abspath(storage_path)
    
    def _get_backup_dir(self) -> str:
        """获取备份目录的绝对路径"""
        backup_path = self.config['storage'].get('backup_dir', 'output/qa_backups')
        
        if not os.path.isabs(backup_path):
            backup_path = os.path.join(base_project_root, backup_path)
        
        return os.path.abspath(backup_path)
    
    def _get_user_dir(self, user_id: str) -> str:
        """获取指定用户的目录路径（按 uid 存储，这样即使用户名变更也不会影响）"""
        return os.path.join(self.storage_dir, str(user_id))
    
    def _get_records_file(self, user_id: str) -> str:
        """获取用户记录 JSON 文件的路径（按 uid）"""
        user_dir = self._get_user_dir(user_id)
        return os.path.join(user_dir, "qa_records.json")
    
    def _load_user_records(self, user_id: str) -> List[Dict[str, Any]]:
        """加载用户现有记录（按 uid）"""
        records_file = self._get_records_file(user_id)
        
        if not os.path.exists(records_file):
            return []
        
        try:
            with open(records_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Failed to load records: {e}")
            return []
    
    def _save_user_records(self, user_id: str, records: List[Dict[str, Any]]) -> None:
        """保存用户记录（按 uid）"""
        user_dir = self._get_user_dir(user_id)
        os.makedirs(user_dir, exist_ok=True)
        
        records_file = self._get_records_file(user_id)
        
        # 保存前如果启用备份则创建备份
        if self.config['storage'].get('enable_backup', True) and os.path.exists(records_file):
            backup_file = os.path.join(
                self.backup_dir,
                f"{user_id}_qa_records_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
            )
            shutil.copy2(records_file, backup_file)
        
        with open(records_file, 'w', encoding='utf-8') as f:
            json.dump(records, f, ensure_ascii=False, indent=2)
    
    def save_temp_record(self, user_id: str, record: Dict[str, Any], username: Optional[str] = None) -> None:
        """
        保存用户的临时处理记录（按 uid）

        Args:
            user_id (str|int): 用户 ID（uid），用于存储路径
            record (Dict): 包含 'processing' 状态的记录数据
            username (str, optional): 用户名，用于在记录中显示
        """
        # 加载现有记录
        records = self._load_user_records(user_id)
        
        # 在开头添加新记录
        # 确保记录包含 uid 和 username
        record.setdefault('uid', str(user_id))
        if username:
            record.setdefault('username', username)
        records.insert(0, record)
        
        # 强制限制最大记录数
        if len(records) > self.max_records:
            removed = records[self.max_records:]
            records = records[:self.max_records]
            print(f"超过最大记录数限制 ({self.max_records})，已删除 {len(removed)} 条旧记录")
        
        # 保存记录
        self._save_user_records(user_id, records)
    
    def update_record(self, user_id: str, record_id: str, record_data: Dict[str, Any]) -> bool:
        """
        更新现有记录
        
        Args:
            user_id (str): 用户 ID
            record_id (str): 要更新的记录 ID
            record_data (Dict): 新的记录数据
            
        Returns:
            bool: 更新成功返回 True，记录未找到返回 False
        """
        records = self._load_user_records(user_id)

        # 查找并更新记录
        for i, rec in enumerate(records):
            if rec.get('record_id') == record_id:
                records[i] = {**rec, **record_data}
                # 确保 uid 保持不变
                records[i].setdefault('uid', str(user_id))
                self._save_user_records(user_id, records)
                return True

        return False

    def delete_record(self, user_id: str, record_id: str) -> bool:
        """
        删除指定的问答记录
        
        Args:
            user_id (str): 用户 ID
            record_id (str): 要删除的记录唯一 ID
        
        Returns:
            bool: 删除成功返回 True，记录未找到返回 False
        """
        records = self._load_user_records(user_id)

        # 查找并移除记录
        original_count = len(records)
        records = [r for r in records if r.get("record_id") != record_id]

        if len(records) == original_count:
            print(f"记录未找到 - 用户 uid: {user_id}, ID: {record_id}")
            return False

        # 保存更新后的记录
        self._save_user_records(user_id, records)
        print(f"记录已删除 - 用户 uid: {user_id}, ID: {record_id}")

        return True
    
    def get_user_records(self, user_id: str, limit: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        获取用户的所有问答记录
        
        Args:
            user_id (str): 用户 ID
            limit (int, optional): 限制返回记录数量（最新的优先）
        
        Returns:
            List[Dict]: 用户的问答记录列表
        """
        records = self._load_user_records(user_id)

        # 如果指定了限制则返回有限数量的记录
        if limit is not None:
            records = records[:limit]

        return records
    
    def get_record_summary(self, user_id: str) -> Dict[str, Any]:
        """
        获取用户记录的统计摘要
        
        Args:
            user_id (str): 用户 ID
        
        Returns:
            Dict: 包含总记录数、成功数、最新时间戳等信息的摘要
        """
        records = self._load_user_records(user_id)

        if not records:
            return {
                "username": None,
                "total_records": 0,
                "success_count": 0,
                "failure_count": 0,
                "processing_count": 0,
                "latest_record": None
            }
        
        # 根据 status 和 success 字段判断状态
        processing_count = sum(1 for r in records if r.get("status") == "processing" or r.get("success") is None)
        success_count = sum(1 for r in records if r.get("success") is True and r.get("status") != "processing")
        failure_count = sum(1 for r in records if r.get("success") is False or r.get("status") == "failed")
        
        return {
            "username": records[0].get('username') if records else None,
            "total_records": len(records),
            "success_count": success_count,
            "failure_count": failure_count,
            "processing_count": processing_count,
            "latest_record": records[0],
            "storage_path": self._get_user_dir(user_id)
        }
    
    def export_records(self, user_id: str, export_path: str) -> bool:
        """
        导出用户记录到指定文件
        
        Args:
            user_id (str): 用户 ID
            export_path (str): 导出文件的绝对路径
        
        Returns:
            bool: 导出成功返回 True
        """
        records = self._load_user_records(user_id)

        try:
            os.makedirs(os.path.dirname(export_path), exist_ok=True)
            with open(export_path, 'w', encoding='utf-8') as f:
                json.dump(records, f, ensure_ascii=False, indent=2)
            print(f"记录已导出: {export_path}")
            return True
        except IOError as e:
            print(f"导出失败: {e}")
            return False


# 使用示例
if __name__ == "__main__":
    # 初始化管理器
    config_file = os.path.join(os.path.dirname(__file__), "../../configs/qa_storage.yaml")
    manager = QAManager(config_file)

    # 示例：获取用户记录
    # records = manager.get_user_records("user123", limit=10)
    # print(json.dumps(records, ensure_ascii=False, indent=2))
    
    # 示例：删除记录
    # manager.delete_record("user123", "a819db39-7356-4c68-b5dd-728f20d4eddb")
    
