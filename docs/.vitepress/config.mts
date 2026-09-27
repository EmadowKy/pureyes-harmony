import { defineConfig } from 'vitepress'
import { withMermaid } from 'vitepress-plugin-mermaid'

export default withMermaid(
  defineConfig({
    title: "Pureyes (清眸)",
    description: "基于鸿蒙系统的多模态智能视觉监控与分析系统",

    themeConfig: {
      siteTitle: '清眸 帮助中心',

      // 顶部导航栏
      nav: [
        { text: '首页', link: '/' },
        { text: '用户指南', link: '/user-guide/01-overview' },
        { text: '开发者文档', link: '/developer-guide/01-architecture-design' },
        { text: '服务器部署', link: '/server-deployment/01-requirements-and-env' }
      ],

      // 左侧边栏菜单
      sidebar: {
        '/user-guide/': [
          {
            text: '开始使用',
            collapsed: false,
            items: [
              { text: '指南首页', link: '/user-guide/01-overview' },
              { text: '快速开始', link: '/user-guide/02-quick-start' },
              { text: '账号登录与安全', link: '/user-guide/03-authentication' }
            ]
          },
          {
            text: '小组与视频',
            collapsed: false,
            items: [
              { text: '小组协作', link: '/user-guide/04-group-collaboration' },
              { text: '监控与回放', link: '/user-guide/05-live-monitoring' },
              { text: '工作区与视频片段', link: '/user-guide/06-workspace-management' },
              { text: '调查问答', link: '/user-guide/07-ai-multimodal-qa' }
            ]
          },
          {
            text: '个人与管理',
            collapsed: false,
            items: [
              { text: '个人中心与模型配置', link: '/user-guide/09-profile-and-settings' },
              { text: '用户管理（管理员）', link: '/user-guide/08-admin-console' }
            ]
          }
        ],
        '/developer-guide/': [
          {
            text: '开发者技术文档',
            items: [
              { text: '01. 系统整体架构设计与数据流', link: '/developer-guide/01-architecture-design' },
              { text: '02. 鸿蒙前端 ArkTS 架构设计', link: '/developer-guide/02-frontend-arkts' },
              { text: '03. 后端 RESTful API 接口规范', link: '/developer-guide/03-backend-flask-api' },
              { text: '04. AI 多模态视觉分析引擎原理', link: '/developer-guide/04-ai-mva-engine' },
              { text: '05. 数据库设计与实体关系模型', link: '/developer-guide/05-database-schema' },
              { text: '06. 鸿蒙原生特色特性接入与技术架构', link: '/developer-guide/06-harmonyos-native-features' }
            ]
          }
        ],
        '/server-deployment/': [
          {
            text: '自建服务器部署手册',
            items: [
              { text: '01. 服务器硬件配置与环境依赖', link: '/server-deployment/01-requirements-and-env' },
              { text: '02. 后端服务部署与运行维护', link: '/server-deployment/02-backend-deployment-guide' }
            ]
          }
        ]
      },

      // 内置本地全文搜索
      search: {
        provider: 'local'
      },

      // 社交链接
      socialLinks: [
        { icon: 'github', link: 'https://github.com/EmadowKy/pureyes-harmony' }
      ],

      // 页脚信息
      footer: {
        message: 'Pureyes (清眸) 鸿蒙多模态视觉监控与分析系统',
        copyright: 'Copyright © 2026'
      }
    }
  })
)
