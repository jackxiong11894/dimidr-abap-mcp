# ABAP MCP Server v2 — 技术架构文档

> 版本: 2.0.0 | 最后更新: 2026-06-13

---

## 1. 项目概述

ABAP MCP Server 是一个独立的 Model Context Protocol (MCP) 服务器，使 AI 助手（Claude、Copilot、Cursor）能够通过 ADT REST API 与 SAP ABAP 系统交互。当前实现 **67 个工具**，覆盖 16 个功能类别 + 2 个元工具 + 1 个 MCP Prompt。

**核心依赖：**
- `@modelcontextprotocol/sdk` ^1.10.1 — MCP 协议栈
- `abap-adt-api` ^7.1.0 — SAP ADT REST API 客户端
- `zod` ^3.24.1 — 参数验证
- TypeScript 5.7+ / Node.js 20+ / ESM

---

## 2. 系统架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│                     MCP Client (Claude/Copilot/Cursor)          │
│                          stdio transport                        │
└────────────────────────────┬────────────────────────────────────┘
                             │ JSON-RPC
┌────────────────────────────▼────────────────────────────────────┐
│  index.ts        入口：Banner + 初始连接 + 启动 stdio 传输       │
│  server.ts       MCP 请求分发：ListTools / CallTool / Prompts   │
│  config.ts       环境变量解析 → 冻结 cfg 对象                    │
│  schemas.ts      30+ Zod schema（参数验证）                      │
│  types.ts        ToolDef / ToolResult / ToolHandler 类型        │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                     tools/  工具层                               │
│  tool-definitions.ts   67 个工具元数据（名称、描述、schema）       │
│  tool-registry.ts      分类注册、核心/延迟工具集                   │
│  handler-map.ts        工具名 → handler 函数分发映射              │
│  mutating-tools.ts     变更操作工具列表（审计/批处理黑名单）        │
│  handlers/             20 个 handler 模块                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                     核心基础设施层                                │
│  adt-client.ts        ADT 客户端单例（懒初始化、连接复用）         │
│  adt-endpoints.ts     ADT REST 端点路径注册中心                   │
│  write-workflow.ts    写工作流：lock→write→DDIC→syntax→activate  │
│  concurrency.ts       写锁串行化 + 有状态会话管理                 │
│  safety.ts            安全守卫（ALLOW_* / 角色 / 包黑名单）       │
│  cache.ts             源码缓存（TTL + 写失效）                   │
│  audit.ts             结构化 JSON 审计日志                       │
│  prompt.ts            abap_develop 6步开发工作流 Prompt           │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                     helpers/  辅助模块                           │
│  json-schema.ts       Zod → JSON Schema 转换                    │
│  ddic-validation.ts   DDIC 字段引用验证                          │
│  method-splice.ts     单方法级别源码剪辑                          │
│  contract.ts          上下文压缩（公共签名提取）                   │
│  documentation.ts     help.sap.com 文档抓取                     │
│  clean-abap.ts        Clean ABAP 静态审查                       │
│  resolve.ts           语法上下文解析（主程序/Include）             │
│  web.ts               Web 内容提取                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│              abap-adt-api (ADTClient)                           │
│  HTTP/HTTPS → SAP ADT REST API (/sap/bc/adt/...)              │
│  支持：直连 / HTTP Proxy / SAProuter / BTP Connectivity Proxy  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. 核心模块详解

### 3.1 入口与服务器 (`index.ts` / `server.ts`)

- `index.ts`: 启动 Banner、初始连接尝试、创建 `StdioServerTransport` 并连接
- `server.ts`: MCP 协议处理器
  - `ListToolsRequestSchema`: 根据 `deferTools` 配置返回可见工具列表
  - `CallToolRequestSchema`: 从 `HANDLER_MAP` 查找并执行 handler
  - `ListPromptsRequestSchema` / `GetPromptRequestSchema`: `abap_develop` 工作流 Prompt
  - 对 `requiresAdt: false` 的工具跳过 ADT 连接

### 3.2 配置系统 (`config.ts`)

从 `.env` 加载并冻结为不可变 `cfg` 对象：

| 分类 | 关键配置 |
|------|---------|
| SAP 连接 | `SAP_URL`, `SAP_USER`, `SAP_PASSWORD`, `SAP_CLIENT`, `SAP_LANGUAGE` |
| 写控制 | `ALLOW_WRITE`, `ALLOW_DELETE`, `ALLOW_EXECUTE`, `BLOCKED_PACKAGES` |
| 治理 | `SAP_ROLE` (viewer/developer/admin), `AUDIT_LOG_FILE` |
| 网络 | `SAP_PROXY_URL`, `SAP_ROUTER`, `SAP_BTP_CONNECTIVITY_PROXY` |
| 运维 | `DEFER_TOOLS`, `SOURCE_CACHE_TTL_MS`, `MAX_DUMPS` |

### 3.3 ADT 客户端 (`adt-client.ts`)

- **单例模式**: 懒初始化，首次调用时 login，后续复用
- **连接活性检测**: `HEAD /sap/bc/adt/core/discovery`
- **网络策略优先级**: BTP Connectivity → SAProuter → HTTP Proxy → 直连 HTTPS
- **自动重连**: 会话过期时透明重建

### 3.4 工具注册与分发

**工具定义流程：**
```
schemas.ts (Zod schema)
    ↓
tool-definitions.ts (name, description, schema)
    ↓
tool-registry.ts (分类、核心工具集、延迟加载)
    ↓
handler-map.ts (工具名 → handler 函数)
```

**延迟加载机制：**
- `DEFER_TOOLS=true` 时仅加载 13 个核心工具
- 其他工具通过 `find_tools` 元工具按需启用
- 约 75-80% 的 token 节省

**Intent Facade（意图门面）：**
- `SAPRead` / `SAPWrite` / `SAPSearch` / `SAPDiagnose`
- 通过 `operation` 分发器路由到具体 handler
- 客户端可用 ~4 个动词替代 67 个工具

### 3.5 写工作流 (`write-workflow.ts`)

这是最关键的流程：

```
lock(objectUrl)
  → setObjectSource(source)
  → validateDdicReferencesInternal(source)  // DDIC 字段验证
  → [并行] unLock() + syntaxCheck()
  → [如果有语法错误: 跳过激活，返回错误]
  → activate(objectUrl)
  → unlock(objectUrl)
  → [finally: 始终释放锁]
```

**锁冲突恢复：**
1. 从错误消息提取请求号 → 带 `corrNr` 重试 lock
2. 查询 `transportInfo` 获取任务号 → 再次重试
3. 仍然失败则抛出错误

### 3.6 安全体系 (`safety.ts`)

多层防护：

1. **角色检查** `assertRoleAllows()`: viewer(只读) / developer(写+执行) / admin(全部)
2. **功能开关**: `assertWriteEnabled()` / `assertDeleteEnabled()`
3. **包保护**: `assertPackageAllowed()` — BLOCKED_PACKAGES 前缀匹配
4. **命名空间**: `assertCustomerNamespace()` — 必须以 Z/Y 开头
5. **只读查询**: `assertSelectOnly()` — 仅允许 SELECT/WITH 语句

### 3.7 并发控制 (`concurrency.ts`)

- **写锁**: `withWriteLock()` — Promise 链串行化，防止并发 ADT 锁冲突
- **有状态会话**: `withStatefulSession()` — lock→write→activate 需要同一会话

### 3.8 缓存 (`cache.ts`)

- 内存 TTL 缓存（默认 30s），键为对象 URL（去除 `/source/main`）
- **写失效**: 每次成功 write/delete 后调用 `invalidateSource()`
- 可通过 `SOURCE_CACHE_TTL_MS=0` 禁用

### 3.9 审计 (`audit.ts`)

- 每次变更操作记录 JSON 行：时间戳、实例、用户、角色、工具、操作、目标、结果
- 输出到 stderr（`AUDIT ` 前缀）+ 可选文件
- `handler-map.ts` 中通过 `withAudit()` 装饰器自动包装变更工具

---

## 4. 工具分类与功能矩阵

| 类别 | 工具数 | 核心功能 |
|------|--------|---------|
| SEARCH | 2 | 对象搜索（通配符）、全文源码搜索 |
| READ | 13 | 源码读取、方法读取、契约、元数据、Where-Used、代码补全、DDIC、表内容 |
| WRITE | 5 | 源码写入（完整工作流）、方法编辑、激活、批量激活、Pretty Print |
| CREATE | 13 | 程序、类、接口、函数组、CDS视图、表、消息类、Metadata Extension、SRVD、SRVB、DCL、BDEF |
| DELETE | 1 | 对象删除 |
| TEST | 2 | ABAP Unit 测试、测试 Include |
| QUALITY | 4 | 语法检查、ATC、DDIC引用验证、Clean ABAP审查 |
| DIAGNOSTICS | 4 | Short Dumps (ST22)、Performance Traces (SAT) |
| TRANSPORT | 3 | 传输信息、传输对象列表、创建传输请求 |
| ABAPGIT | 2 | 仓库列表、Pull |
| QUERY | 4 | 工作流分析、SELECT查询、未激活对象、代码片段执行 |
| DOCUMENTATION | 5 | ABAP关键字文档、类文档、最佳实践、Clean ABAP、语法搜索 |
| WEBSEARCH | 2 | URL内容提取、SAP Web搜索（Tavily） |
| BATCH | 1 | 并行只读批量操作 |
| ANALYSIS | 2 | 调用图、死代码检测 |
| INTENT | 4 | SAPRead/SAPWrite/SAPSearch/SAPDiagnose 意图门面 |
| META | 2 | find_tools / list_tools |

---

## 5. 已有 DDIC 功能分析

### 已实现的 DDIC 相关工具

| 工具 | 类型 | ADT 端点 | 功能 |
|------|------|----------|------|
| `get_ddic_element` | READ | `/sap/bc/adt/ddic/elements` | 读取表/视图/数据元素/域的元数据 |
| `get_table_fields` | READ | `client.tableContents()` | 获取表字段目录 |
| `get_table_contents` | READ | `/sap/bc/adt/datapreview/ddic` | 读取表内容 |
| `create_database_table` | CREATE | `/sap/bc/adt/ddic/tables` | 创建透明表（仅创建空壳，无字段定义） |
| `validate_ddic_references` | QUALITY | `client.ddicElement()` | 验证代码中的字段引用 |

### 缺失的 DDIC CRUD 功能

**当前不支持的操作：**

| 操作 | DDIC 对象类型 | 说明 |
|------|-------------|------|
| **Create** 带字段定义 | TABL | 创建表时定义字段、类型、键、长度等 |
| **Create** 数据元素 | DTEL | 创建 Data Element |
| **Create** 域 | DOMA | 创建 Domain |
| **Create** 结构 | TABL (结构) | 创建 Structure（非透明表） |
| **Create** 表类型 | TTYP | 创建 Table Type |
| **Create** 视图 | VIEW | 创建 View |
| **Update** 表字段 | TABL | 修改表结构（添加/删除/修改字段） |
| **Update** 数据元素 | DTEL | 修改数据元素属性 |
| **Update** 域 | DOMA | 修改域属性 |
| **Delete** 数据元素 | DTEL | 删除数据元素 |
| **Delete** 域 | DOMA | 删除域 |
| **Delete** 表类型 | TTYP | 删除表类型 |
| **Read** 表完整定义 | TABL | 包含字段、索引、锁对象等完整结构 |

---

## 6. 如何扩展 DDIC CRUD 功能

### 6.1 扩展架构模式

新增工具需修改 **6 个文件**，遵循现有模式：

```
1. src/schemas.ts              → 添加 Zod 验证 schema
2. src/tools/tool-definitions.ts → 添加工具元数据
3. src/tools/handlers/ddic.ts  → 新建 handler 模块（推荐独立文件）
4. src/tools/handler-map.ts    → 注册 handler 到分发映射
5. src/tools/tool-registry.ts  → 添加到 DDIC 分类
6. src/tools/mutating-tools.ts → 变更操作加入审计列表
```

### 6.2 新增 DDIC 工具设计

#### 6.2.1 创建数据元素 (`create_data_element`)

```typescript
// schemas.ts
export const S_CreateDataElement = z.object({
  name:        z.string().min(1).max(30).describe("数据元素名称，必须以 Z 或 Y 开头"),
  description: z.string().max(40).describe("短描述"),
  devClass:    z.string().describe("包名"),
  transport:   z.string().optional().describe("传输请求号"),
  domain:      z.string().optional().describe("关联的域名"),
  dataType:    z.enum(["CHAR", "NUMC", "INT1", "INT2", "INT4", "INT8",
    "DEC", "CURR", "QUAN", "FLTP", "DATE", "TIME", "TIMS",
    "XSTRING", "STRING", "RAW", "INT2"]).describe("数据类型"),
  length:      z.number().int().min(1).max(5000).optional().describe("长度"),
  decimals:    z.number().int().min(0).max(63).optional().describe("小数位"),
});

// tool-definitions.ts
{
  name: "create_data_element",
  description: "创建新的数据元素 (DTEL)。定义 ABAP 字段的语义类型。⚠️ 需要 ALLOW_WRITE=true。",
  schema: S.S_CreateDataElement,
}

// handlers/ddic.ts
export async function handleCreateDataElement(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_CreateDataElement.parse(args);
  assertPackageAllowed(p.devClass);
  assertCustomerNamespace(p.name, ["Z", "Y"]);
  const n = p.name.toUpperCase();
  const url = `${ADT_DDIC_DATA_ELEMENTS}/${n.toLowerCase()}`;

  // 构建 XML 创建请求
  const responsible = client.httpClient.username.toUpperCase();
  const body = [
    `<?xml version="1.0" encoding="UTF-8"?>`,
    `<blue:blueSource xmlns:blue="http://www.sap.com/wbobj/blue"`,
    `  xmlns:adtcore="http://www.sap.com/adt/core"`,
    `  xmlns:dTEL="http://www.sap.com/adt/ddic/dataelements"`,
    `  adtcore:description="${encXml(p.description)}"`,
    `  adtcore:name="${n}" adtcore:type="DTEL/DE"`,
    `  adtcore:language="EN" adtcore:masterLanguage="EN"`,
    `  adtcore:responsible="${responsible}">`,
    `  <adtcore:packageRef adtcore:name="${p.devClass}"/>`,
    `  <dTEL:dataElement dTEL:category="${p.domain ? 'derived' : 'predefined'}">`,
    p.domain ? `    <dTEL:domain adtcore:name="${p.domain.toUpperCase()}"/>` : '',
    !p.domain ? `    <dTEL:abapType dTEL:typeName="${p.dataType}" dTEL:length="${p.length ?? 10}" dTEL:decimals="${p.decimals ?? 0}"/>` : '',
    `  </dTEL:dataElement>`,
    `</blue:blueSource>`,
  ].join("\n");

  const qs: Record<string, string> = {};
  if (p.transport) qs.corrNr = p.transport;

  await client.httpClient.request(ADT_DDIC_DATA_ELEMENTS, {
    method: "POST",
    headers: { "Content-Type": "application/*" },
    qs,
    body,
  });

  return ok(`✅ 数据元素 '${n}' 已创建\nURI: ${url}`);
}
```

#### 6.2.2 创建域 (`create_domain`)

```typescript
// schemas.ts
export const S_CreateDomain = z.object({
  name:        z.string().min(1).max(30).describe("域名，必须以 Z 或 Y 开头"),
  description: z.string().max(40).describe("短描述"),
  devClass:    z.string().describe("包名"),
  transport:   z.string().optional(),
  dataType:    z.enum(["CHAR", "NUMC", "INT1", "INT2", "INT4", "INT8",
    "DEC", "CURR", "QUAN", "FLTP", "DATE", "TIME", "TIMS",
    "XSTRING", "STRING", "RAW"]).describe("数据类型"),
  length:      z.number().int().min(1).max(5000).describe("长度"),
  decimals:    z.number().int().min(0).max(63).default(0).optional(),
});

// ADT 端点
export const ADT_DDIC_DOMAINS = "/sap/bc/adt/ddic/domains";
```

#### 6.2.3 创建结构 (`create_structure`)

```typescript
// schemas.ts
export const S_CreateStructure = z.object({
  name:        z.string().min(1).max(30).describe("结构名称，必须以 Z 或 Y 开头"),
  description: z.string().max(40).describe("短描述"),
  devClass:    z.string().describe("包名"),
  transport:   z.string().optional(),
  fields: z.array(z.object({
    fieldName:  z.string().describe("字段名"),
    dataType:   z.string().describe("数据类型 (DATAELEMENT 或内置类型)"),
    length:     z.number().optional().describe("长度"),
    decimals:   z.number().optional().describe("小数位"),
    notNull:    z.boolean().optional().describe("是否 NOT NULL"),
  })).min(1).max(100).describe("字段列表"),
});

// ADT 端点 — 复用 ADT_DDIC_TABLES，但 type 为 TABL/DS（结构）
export const ADT_DDIC_STRUCTURES = "/sap/bc/adt/ddic/structures";
```

#### 6.2.4 修改表结构 (`alter_table`)

```typescript
// schemas.ts
export const S_AlterTable = z.object({
  tableName:   z.string().describe("表名"),
  transport:   z.string().optional(),
  addFields: z.array(z.object({
    fieldName: z.string().describe("字段名"),
    dataType:  z.string().describe("数据元素或内置类型"),
    position:  z.number().optional().describe("位置（可选，默认追加）"),
  })).optional().describe("要添加的字段"),
  dropFields: z.array(z.string()).optional().describe("要删除的字段名"),
  modifyFields: z.array(z.object({
    fieldName:    z.string().describe("字段名"),
    newDataType:  z.string().optional().describe("新数据类型"),
    newLength:    z.number().optional().describe("新长度"),
    newDecimals:  z.number().optional().describe("新小数位"),
  })).optional().describe("要修改的字段"),
});
```

#### 6.2.5 读取完整表定义 (`get_table_definition`)

```typescript
// schemas.ts
export const S_GetTableDefinition = z.object({
  tableName: z.string().describe("表名"),
});

// handler — 返回比 get_ddic_element 更详细的信息
// 包括：字段列表、索引、锁对象、外键、搜索帮助等
```

### 6.3 DDIC 端点注册 (`adt-endpoints.ts`)

```typescript
// 新增 DDIC 端点
export const ADT_DDIC_DATA_ELEMENTS = "/sap/bc/adt/ddic/dataelements";
export const ADT_DDIC_DOMAINS = "/sap/bc/adt/ddic/domains";
export const ADT_DDIC_STRUCTURES = "/sap/bc/adt/ddic/structures";
export const ADT_DDIC_TABLE_TYPES = "/sap/bc/adt/ddic/tabletypes";
export const ADT_DDIC_VIEWS = "/sap/bc/adt/ddic/views";
```

### 6.4 Intent Facade 扩展

在 `intent.ts` 的 `READ_OPS` 和 `WRITE_OPS` 中添加新操作：

```typescript
const READ_OPS: Record<string, string> = {
  // ...existing...
  table_definition: "get_table_definition",
  data_element: "get_data_element_info",
  domain: "get_domain_info",
};

const WRITE_OPS: Record<string, string> = {
  // ...existing...
  create_data_element: "create_data_element",
  create_domain: "create_domain",
  create_structure: "create_structure",
  alter_table: "alter_table",
};
```

### 6.5 分类注册 (`tool-registry.ts`)

```typescript
export const TOOL_CATEGORIES: Record<string, string[]> = {
  // ...existing...
  DDIC: [
    "get_ddic_element", "get_table_fields", "get_table_contents",
    "create_database_table", "create_data_element", "create_domain",
    "create_structure", "alter_table", "get_table_definition",
    "validate_ddic_references",
  ],
};
```

### 6.6 变更工具审计 (`mutating-tools.ts`)

```typescript
export const AUDIT_WRAPPED_TOOLS: ReadonlyArray<[string, AuditEvent["action"]]> = [
  // ...existing...
  ["create_data_element",   "write"],
  ["create_domain",         "write"],
  ["create_structure",      "write"],
  ["alter_table",           "write"],
];
```

---

## 7. ADT REST API DDIC 端点参考

| 操作 | HTTP 方法 | 端点 | 说明 |
|------|----------|------|------|
| 创建表 | POST | `/sap/bc/adt/ddic/tables` | type=TABL/DT |
| 读取表 | GET | `/sap/bc/adt/ddic/tables/{name}` | 获取完整定义 |
| 修改表 | PUT | `/sap/bc/adt/ddic/tables/{name}` | 更新表定义 |
| 删除表 | DELETE | `/sap/bc/adt/ddic/tables/{name}` | 删除表 |
| 创建数据元素 | POST | `/sap/bc/adt/ddic/dataelements` | type=DTEL/DE |
| 读取数据元素 | GET | `/sap/bc/adt/ddic/dataelements/{name}` | |
| 创建域 | POST | `/sap/bc/adt/ddic/domains` | type=DOMA/DE |
| 读取域 | GET | `/sap/bc/adt/ddic/domains/{name}` | |
| 创建表类型 | POST | `/sap/bc/adt/ddic/tabletypes` | type=TTYP/DT |
| DDIC 元素查询 | GET | `/sap/bc/adt/ddic/elements` | 通用元数据查询 |

**注意：** `abap-adt-api` 库可能不直接支持所有 DDIC 操作。对于不支持的操作，需使用 `client.httpClient.request()` 直接发送 HTTP 请求（参考 `create_database_table` 和 `create_behavior_definition` 的实现模式）。

---

## 8. 完整扩展示例：添加数据元素 CRUD

### 步骤 1: 添加端点 (`src/adt-endpoints.ts`)

```typescript
export const ADT_DDIC_DATA_ELEMENTS = "/sap/bc/adt/ddic/dataelements";
export const ADT_DDIC_DOMAINS = "/sap/bc/adt/ddic/domains";
```

### 步骤 2: 添加 Schema (`src/schemas.ts`)

```typescript
export const S_CreateDataElement = z.object({
  name: z.string().min(1).max(30).describe("数据元素名称，必须以 Z 或 Y 开头"),
  description: z.string().max(40).describe("短描述"),
  devClass: z.string().describe("包名"),
  transport: z.string().optional(),
  domain: z.string().optional().describe("关联的域名（可选）"),
  dataType: z.enum(["CHAR","NUMC","INT1","INT2","INT4","INT8","DEC","CURR","QUAN","FLTP","DATE","TIME","TIMS","XSTRING","STRING","RAW"]).describe("数据类型（无域时必填）"),
  length: z.number().int().min(1).max(5000).optional().describe("长度"),
  decimals: z.number().int().min(0).max(63).optional().describe("小数位"),
});
```

### 步骤 3: 创建 Handler (`src/tools/handlers/ddic.ts`)

```typescript
import type { ADTClient } from "abap-adt-api";
import type { ToolResult } from "../../types.js";
import { S_CreateDataElement, S_CreateDomain } from "../../schemas.js";
import { ADT_DDIC_DATA_ELEMENTS, ADT_DDIC_DOMAINS } from "../../adt-endpoints.js";
import { assertWriteEnabled, assertPackageAllowed, assertCustomerNamespace } from "../../safety.js";

const encXml = (s: string) => s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
function ok(text: string): ToolResult { return { content: [{ type: "text", text }] }; }

export async function handleCreateDataElement(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_CreateDataElement.parse(args);
  assertPackageAllowed(p.devClass);
  assertCustomerNamespace(p.name, ["Z", "Y"]);
  const n = p.name.toUpperCase();
  const responsible = client.httpClient.username.toUpperCase();

  // 构建 XML（参考 SAP ADT Data Element 创建格式）
  const body = [
    `<?xml version="1.0" encoding="UTF-8"?>`,
    `<blue:blueSource xmlns:blue="http://www.sap.com/wbobj/blue"`,
    `  xmlns:adtcore="http://www.sap.com/adt/core"`,
    `  xmlns:dTEL="http://www.sap.com/adt/ddic/dataelements"`,
    `  xmlns:DOMA="http://www.sap.com/adt/ddic/domains"`,
    `  adtcore:description="${encXml(p.description)}"`,
    `  adtcore:name="${n}" adtcore:type="DTEL/DE"`,
    `  adtcore:language="EN" adtcore:masterLanguage="EN"`,
    `  adtcore:responsible="${responsible}">`,
    `  <adtcore:packageRef adtcore:name="${p.devClass}"/>`,
    `  <dTEL:dataElement>`,
    p.domain
      ? `    <DOMA:domain adtcore:name="${p.domain.toUpperCase()}"/>`
      : `    <dTEL:abapType dTEL:typeName="${p.dataType}" dTEL:length="${p.length ?? 10}" dTEL:decimals="${p.decimals ?? 0}"/>`,
    `  </dTEL:dataElement>`,
    `</blue:blueSource>`,
  ].join("\n");

  const qs: Record<string, string> = {};
  if (p.transport) qs.corrNr = p.transport;

  await client.httpClient.request(ADT_DDIC_DATA_ELEMENTS, {
    method: "POST",
    headers: { "Content-Type": "application/*" },
    qs,
    body,
  });

  const url = `${ADT_DDIC_DATA_ELEMENTS}/${n.toLowerCase()}`;
  return ok(`✅ 数据元素 '${n}' 已创建\nURI: ${url}`);
}

export async function handleGetTableDefinition(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  const { tableName } = z.object({ tableName: z.string() }).parse(args);
  const n = tableName.toUpperCase();
  const url = `/sap/bc/adt/ddic/tables/${n.toLowerCase()}`;

  // 读取表完整定义（比 get_ddic_element 更详细）
  try {
    const resp = await client.httpClient.request(url, {
      headers: { Accept: "application/vnd.sap.adt.tables.v2+xml" },
    });
    return ok(resp.body);
  } catch {
    // 回退到 ddicElement
    const ddic = await client.ddicElement(n);
    return ok(JSON.stringify(ddic, null, 2));
  }
}
```

### 步骤 4: 注册 Handler (`src/tools/handler-map.ts`)

```typescript
import { handleCreateDataElement, handleGetTableDefinition } from "./handlers/ddic.js";

// 在 HANDLER_MAP 中添加
["create_data_element",    handleCreateDataElement],
["get_table_definition",   handleGetTableDefinition],
```

### 步骤 5: 注册工具定义 (`src/tools/tool-definitions.ts`)

```typescript
{ name: "create_data_element",
  description: "创建新的数据元素 (DTEL)。定义 ABAP 字段的语义类型。⚠️ 需要 ALLOW_WRITE=true。",
  schema: S.S_CreateDataElement },
{ name: "get_table_definition",
  description: "读取表的完整定义：字段列表、数据类型、键、索引、外键、搜索帮助等。",
  schema: S.S_GetTableDefinition },
```

### 步骤 6: 分类与审计 (`tool-registry.ts` + `mutating-tools.ts`)

```typescript
// tool-registry.ts
DDIC: ["get_ddic_element", "get_table_fields", "get_table_contents",
       "create_database_table", "create_data_element", "get_table_definition",
       "validate_ddic_references"],

// mutating-tools.ts
["create_data_element", "write"],
```

---

## 9. DDIC 扩展的注意事项

### 9.1 ADT API 限制

- `abap-adt-api` 对 DDIC 对象的支持有限，多数创建操作需要 `client.httpClient.request()` 直接发送 HTTP
- XML 命名空间必须严格匹配 SAP ADT 端点要求
- 部分操作需要 SAP NetWeaver 7.50+ 版本

### 9.2 错误处理模式

参考现有 `create_database_table` 的防御模式：

```typescript
try {
  await client.httpClient.request(url, { method: "POST", ... });
} catch (createErr) {
  const errMsg = createErr instanceof Error ? createErr.message : String(createErr);
  // "already exist" = 真正的重复
  if (errMsg.includes("already exist") || errMsg.includes("SADT_RESOURCE/1")) throw createErr;
  // 验证是否实际创建成功
  try {
    await client.objectStructure(objectUrl);
    return ok(`✅ 创建成功（ADT 返回非致命错误）`);
  } catch { throw createErr; }
}
```

### 9.3 修改操作的锁流程

修改 DDIC 对象需要完整的写工作流：
```
lock → 读取当前定义 → 合并修改 → setObjectSource → syntaxCheck → activate → unlock
```

### 9.4 传输请求

所有变更操作应支持 `transport` 参数，通过 `qs.corrNr` 传递给 ADT。

### 9.5 缓存失效

任何 DDIC 修改操作后应调用 `invalidateSource()` 清除相关缓存。

---

## 10. 测试策略

```bash
# 单元测试（无需 SAP 连接）
npm test

# 开发模式测试
npm run dev

# 构建验证
npm run build
```

- `test/*.test.ts` — Vitest，覆盖纯函数（Clean ABAP 解析、SAProuter 路由解析、安全守卫、配置解析）
- 新增 DDIC handler 应在 `test/` 目录添加对应的 mock 测试

---

## 11. 文件修改清单（DDIC CRUD 扩展）

| 文件 | 修改类型 | 说明 |
|------|---------|------|
| `src/adt-endpoints.ts` | 编辑 | 添加 DDIC 新端点常量 |
| `src/schemas.ts` | 编辑 | 添加 Create/Read/Alter DDIC schema |
| `src/tools/handlers/ddic.ts` | **新建** | DDIC CRUD handler 模块 |
| `src/tools/tool-definitions.ts` | 编辑 | 添加工具元数据 |
| `src/tools/handler-map.ts` | 编辑 | 注册新 handler |
| `src/tools/tool-registry.ts` | 编辑 | 添加 DDIC 分类 |
| `src/tools/mutating-tools.ts` | 编辑 | 添加变更工具到审计列表 |
| `src/tools/handlers/intent.ts` | 编辑 | 扩展 Intent Facade 路由 |
| `src/schemas.ts` (Intent) | 编辑 | 扩展 S_IntentRead/Write 描述 |
| `test/ddic.test.ts` | **新建** | DDIC 工具单元测试 |
| `CLAUDE.md` | 编辑 | 更新工具计数和分类 |
| `readme.md` | 编辑 | 更新用户文档 |
| `DOCUMENTATION.md` | 编辑 | 添加 DDIC 工具参考 |

---

## 12. 总结

当前项目架构清晰、模块化良好，扩展 DDIC CRUD 功能的最佳路径是：

1. **独立 handler 文件** `src/tools/handlers/ddic.ts` — 隔离 DDIC 业务逻辑
2. **直接 HTTP 调用** — 绕过 `abap-adt-api` 的限制，使用 `client.httpClient.request()`
3. **复用现有基础设施** — 安全守卫、审计、缓存失效、写锁全部继承
4. **Intent Facade 扩展** — 通过 `SAPRead(table_definition=...)` / `SAPWrite(create_data_element=...)` 暴露
5. **渐进式实现** — 先实现 Create + Read，再补充 Update + Delete
