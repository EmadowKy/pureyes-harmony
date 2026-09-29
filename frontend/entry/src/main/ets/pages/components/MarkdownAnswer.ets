import { webview } from '@kit.ArkWeb'
import { common } from '@kit.AbilityKit'

class MarkdownBridge {
  onHeightChange: (height: number) => void = (_height: number): void => {};
  onVideoClick: (video: number, time: string) => void = (_video: number, _time: string): void => {};
  onExternalLink: (url: string) => void = (_url: string): void => {};

  onHeight(height: number): void {
    this.onHeightChange(height);
  }

  onTimestamp(video: number, time: string): void {
    this.onVideoClick(video, time);
  }

  onLink(url: string): void {
    this.onExternalLink(url);
  }
}

@Component
export struct MarkdownAnswer {
  @Prop @Watch('renderMarkdown') markdown: string = '';
  @Prop @Watch('renderMarkdown') failed: boolean = false;
  onTimestampClick: (video: number, time: string) => void = (_video: number, _time: string): void => {};

  @State private contentHeight: number = 28;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: MarkdownBridge = new MarkdownBridge();
  private pageReady: boolean = false;
  private contentWidth: number = 0;
  private renderVersion: number = 0;

  aboutToDisappear(): void {
    this.pageReady = false;
    this.renderVersion++;
  }

  aboutToAppear(): void {
    this.bridge.onHeightChange = (height: number): void => {
      if (Number.isFinite(height) && height > 0) {
        this.contentHeight = Math.max(28, Math.ceil(height));
      }
    };
    this.bridge.onVideoClick = (video: number, time: string): void => {
      if (Number.isInteger(video) && video > 0 && /^\d{1,3}:\d{2}(?::\d{2})?$/.test(time)) {
        this.onTimestampClick(video, time);
      }
    };
    this.bridge.onExternalLink = (url: string): void => {
      if (/^https?:\/\//i.test(url) || /^mailto:/i.test(url)) {
        try {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
          context.openLink(url).catch((): void => {});
        } catch (_error) {
          // A link must never interrupt reading the answer.
        }
      }
    };
  }

  private renderMarkdown(): void {
    if (this.pageReady) {
      const version = ++this.renderVersion;
      // JSON serialization makes the answer a JavaScript string, never executable source.
      // Also read the height directly: a missed proxy callback must not leave a 28vp viewport.
      this.controller.runJavaScript(
        `window.renderAnswer(${JSON.stringify(this.markdown)}, ${this.failed}, ${this.contentWidth});`
      ).then((result: string): void => {
        if (!this.pageReady || version !== this.renderVersion) {
          return;
        }
        const height = Number(result);
        if (Number.isFinite(height) && height > 0) {
          this.contentHeight = Math.max(28, Math.ceil(height));
        }
      }).catch((): void => {});
    }
  }

  build() {
    Web({ src: $rawfile('answer_markdown.html'), controller: this.controller })
      .javaScriptAccess(true)
      .javaScriptProxy({
        object: this.bridge,
        name: 'markdownBridge',
        methodList: ['onHeight', 'onTimestamp', 'onLink'],
        controller: this.controller
      })
      .onPageEnd((): void => {
        this.pageReady = true;
        this.renderMarkdown();
      })
      .width('100%')
      .height(this.contentHeight)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        const width = Number(newArea.width);
        if (Number.isFinite(width) && width > 0 && Math.abs(width - this.contentWidth) > 1) {
          this.contentWidth = width;
          this.renderMarkdown();
        }
      })
      .backgroundColor(Color.Transparent)
  }
}

