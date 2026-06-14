/**
 * DDIC CRUD tool handlers: create_domain, update_domain,
 * create_data_element, update_data_element,
 * create_structure, update_structure
 *
 * Calls the custom ICF endpoint /sap/bc/zddic_crud handled by ZCL_ADT_DDIC_HANDLER.
 * Object type (doma|dtel|stru) is passed as URL path segment:
 *   POST /sap/bc/zddic_crud/{type}        for create
 *   PUT  /sap/bc/zddic_crud/{type}/{name}  for update
 *
 * Unlike the standard ADT lock/write/activate workflow (used by write_abap_source),
 * this custom endpoint handles the full lifecycle server-side:
 *   - DDIF_*_PUT (write DDIC tables)
 *   - DDIF_*_ACTIVATE (activate object)
 *   - Transport assignment (if corrNr provided)
 *   - Object-level locking
 *
 * The MCP-side withWriteLock ensures concurrent write operations are serialized.
 */

import type { ADTClient } from "abap-adt-api";
import { ErrorCode, McpError } from "@modelcontextprotocol/sdk/types.js";
import type { ToolResult } from "../../types.js";
import {
  S_CreateDomain, S_UpdateDomain,
  S_CreateDataElement, S_UpdateDataElement,
  S_CreateStructure, S_UpdateStructure,
} from "../../schemas.js";
import { ADT_ZDDIC_CRUD } from "../../adt-endpoints.js";
import { assertWriteEnabled, assertPackageAllowed, assertCustomerNamespace } from "../../safety.js";
import { withWriteLock, withStatefulSession } from "../../concurrency.js";
import { audit } from "../../audit.js";

// ── Helpers ─────────────────────────────────────────────────────────────────

function ok(text: string): ToolResult { return { content: [{ type: "text", text }] }; }
function err(text: string): ToolResult { return { content: [{ type: "text", text }], isError: true }; }

/** Build URL for DDIC CRUD endpoint */
function ddicUrl(type: string, name?: string): string {
  const base = `${ADT_ZDDIC_CRUD}/${type}`;
  return name ? `${base}/${encodeURIComponent(name.toUpperCase())}` : base;
}

/** Common HTTP request wrapper with error handling */
async function ddicRequest(
  client: ADTClient,
  method: "POST" | "PUT",
  type: string,
  body: Record<string, unknown>,
  name?: string,
  transport?: string,
): Promise<unknown> {
  const url = ddicUrl(type, name);
  const qs: Record<string, string> = {};
  if (transport) qs.corrNr = transport;

  try {
    return await client.httpClient.request(url, {
      method,
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      qs,
      body: JSON.stringify(body),
    });
  } catch (e) {
    const errMsg = e instanceof Error ? e.message : String(e);

    // Handle "already exists" errors with user-friendly message
    if (errMsg.includes("already exist") || errMsg.includes("SADT_RESOURCE/1")) {
      throw new McpError(ErrorCode.InvalidRequest, `Object '${name}' already exists. Use update operation instead.`);
    }

    // Handle lock conflicts
    if (errMsg.includes("locked") || errMsg.includes("ENQUEUE")) {
      throw new McpError(ErrorCode.InvalidRequest, `Object '${name}' is locked by another user. Try again later or unlock in SE03.`);
    }

    // Re-throw with context
    throw new McpError(ErrorCode.InternalError, `DDIC ${method} ${type}/${name ?? ""} failed: ${errMsg}`);
  }
}

// ── Domain ────────────────────────────────────────────────────────────────

export async function handleCreateDomain(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_CreateDomain.parse(args);
  assertPackageAllowed(p.devClass);
  assertCustomerNamespace(p.name, ["Z", "Y"]);
  const n = p.name.toUpperCase();

  const body: Record<string, unknown> = {
    type:        "doma",
    name:        n,
    description: p.description,
    datatype:    p.datatype.toUpperCase(),
    length:      p.length,
    decimals:    p.decimals ?? 0,
    package:     p.devClass,
  };

  return withWriteLock(() => withStatefulSession(client, async () => {
    await ddicRequest(client, "POST", "doma", body, undefined, p.transport);
    audit({ tool: "create_domain", action: "write", target: n, outcome: "success" });
    return ok(`✅ Domain '${n}' created and activated

Package: ${p.devClass}${p.transport ? `\nTransport: ${p.transport}` : ""}

Next steps:
  create_data_element with domain='${n}'`);
  }));
}

export async function handleUpdateDomain(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_UpdateDomain.parse(args);
  assertPackageAllowed(p.devClass ?? "");
  assertCustomerNamespace(p.name, ["Z", "Y"]);
  const n = p.name.toUpperCase();

  const body: Record<string, unknown> = { type: "doma", name: n };
  if (p.description !== undefined) body.description = p.description;
  if (p.datatype !== undefined) body.datatype = p.datatype.toUpperCase();
  if (p.length !== undefined) body.length = p.length;
  if (p.decimals !== undefined) body.decimals = p.decimals;
  if (p.devClass !== undefined) body.package = p.devClass;

  return withWriteLock(() => withStatefulSession(client, async () => {
    await ddicRequest(client, "PUT", "doma", body, n, p.transport);
    audit({ tool: "update_domain", action: "write", target: n, outcome: "success" });
    return ok(`✅ Domain '${n}' updated and activated`);
  }));
}

// ── Data Element ──────────────────────────────────────────────────────────

export async function handleCreateDataElement(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_CreateDataElement.parse(args);
  assertPackageAllowed(p.devClass);
  assertCustomerNamespace(p.name, ["Z", "Y"]);
  const n = p.name.toUpperCase();

  const body: Record<string, unknown> = {
    type:         "dtel",
    name:         n,
    description:  p.description,
    domain:       p.domain.toUpperCase(),
    headingLabel: p.headingLabel ?? "",
    shortLabel:   p.shortLabel ?? "",
    mediumLabel:  p.mediumLabel ?? "",
    longLabel:    p.longLabel ?? "",
    package:      p.devClass,
  };

  return withWriteLock(() => withStatefulSession(client, async () => {
    await ddicRequest(client, "POST", "dtel", body, undefined, p.transport);
    audit({ tool: "create_data_element", action: "write", target: n, outcome: "success" });
    return ok(`✅ Data element '${n}' created and activated

Domain: ${p.domain.toUpperCase()}
Package: ${p.devClass}${p.transport ? `\nTransport: ${p.transport}` : ""}

Next steps:
  create_structure with field rollname='${n}'`);
  }));
}

export async function handleUpdateDataElement(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_UpdateDataElement.parse(args);
  assertPackageAllowed(p.devClass ?? "");
  assertCustomerNamespace(p.name, ["Z", "Y"]);
  const n = p.name.toUpperCase();

  const body: Record<string, unknown> = { type: "dtel", name: n };
  if (p.description !== undefined) body.description = p.description;
  if (p.domain !== undefined) body.domain = p.domain.toUpperCase();
  if (p.headingLabel !== undefined) body.headingLabel = p.headingLabel;
  if (p.shortLabel !== undefined) body.shortLabel = p.shortLabel;
  if (p.mediumLabel !== undefined) body.mediumLabel = p.mediumLabel;
  if (p.longLabel !== undefined) body.longLabel = p.longLabel;
  if (p.devClass !== undefined) body.package = p.devClass;

  return withWriteLock(() => withStatefulSession(client, async () => {
    await ddicRequest(client, "PUT", "dtel", body, n, p.transport);
    audit({ tool: "update_data_element", action: "write", target: n, outcome: "success" });
    return ok(`✅ Data element '${n}' updated and activated`);
  }));
}

// ── Structure ─────────────────────────────────────────────────────────────

export async function handleCreateStructure(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_CreateStructure.parse(args);
  assertPackageAllowed(p.devClass);
  assertCustomerNamespace(p.name, ["Z", "Y"]);
  const n = p.name.toUpperCase();

  const body: Record<string, unknown> = {
    type:        "stru",
    name:        n,
    description: p.description,
    fields:      p.fields ?? [],
    package:     p.devClass,
  };

  return withWriteLock(() => withStatefulSession(client, async () => {
    await ddicRequest(client, "POST", "stru", body, undefined, p.transport);
    audit({ tool: "create_structure", action: "write", target: n, outcome: "success" });
    const fieldCount = p.fields?.length ?? 0;
    return ok(`✅ Structure '${n}' created and activated

Fields: ${fieldCount}
Package: ${p.devClass}${p.transport ? `\nTransport: ${p.transport}` : ""}`);
  }));
}

export async function handleUpdateStructure(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_UpdateStructure.parse(args);
  assertPackageAllowed(p.devClass ?? "");
  assertCustomerNamespace(p.name, ["Z", "Y"]);
  const n = p.name.toUpperCase();

  const body: Record<string, unknown> = { type: "stru", name: n };
  if (p.description !== undefined) body.description = p.description;
  if (p.fields !== undefined) body.fields = p.fields;
  if (p.devClass !== undefined) body.package = p.devClass;

  return withWriteLock(() => withStatefulSession(client, async () => {
    await ddicRequest(client, "PUT", "stru", body, n, p.transport);
    audit({ tool: "update_structure", action: "write", target: n, outcome: "success" });
    return ok(`✅ Structure '${n}' updated and activated`);
  }));
}
