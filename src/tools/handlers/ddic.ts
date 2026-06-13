/**
 * DDIC CRUD tool handlers: create_domain, update_domain,
 * create_data_element, update_data_element,
 * create_structure, update_structure
 *
 * Calls the custom ICF endpoint /sap/bc/zddic_crud handled by ZCL_ADT_DDIC_HANDLER.
 */

import type { ADTClient } from "abap-adt-api";
import type { ToolResult } from "../../types.js";
import {
  S_CreateDomain, S_UpdateDomain,
  S_CreateDataElement, S_UpdateDataElement,
  S_CreateStructure, S_UpdateStructure,
} from "../../schemas.js";
import { ADT_ZDDIC_CRUD } from "../../adt-endpoints.js";
import { assertWriteEnabled, assertPackageAllowed, assertCustomerNamespace } from "../../safety.js";

function ok(text: string): ToolResult { return { content: [{ type: "text", text }] }; }

// ── Domain ────────────────────────────────────────────────────────────────

export async function handleCreateDomain(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_CreateDomain.parse(args);
  assertPackageAllowed(p.devClass);
  assertCustomerNamespace(p.name, ["Z", "Y"]);

  const body = JSON.stringify({
    name:        p.name.toUpperCase(),
    description: p.description,
    datatype:    p.datatype.toUpperCase(),
    length:      p.length,
    decimals:    p.decimals ?? 0,
    package:     p.devClass,
    transport:   p.transport ?? "",
  });

  const qs: Record<string, string> = {};
  if (p.transport) qs.corrNr = p.transport;

  const resp = await client.httpClient.request(`${ADT_ZDDIC_CRUD}/doma`, {
    method:  "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    qs,
    body,
  });

  return ok(`✅ Domain '${p.name.toUpperCase()}' created\n\n${JSON.stringify(resp, null, 2)}`);
}

export async function handleUpdateDomain(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_UpdateDomain.parse(args);
  assertCustomerNamespace(p.name, ["Z", "Y"]);

  const body = JSON.stringify({
    description: p.description,
    datatype:    p.datatype?.toUpperCase(),
    length:      p.length,
    decimals:    p.decimals,
    package:     p.devClass ?? "",
    transport:   p.transport ?? "",
  });

  const qs: Record<string, string> = {};
  if (p.transport) qs.corrNr = p.transport;

  const resp = await client.httpClient.request(`${ADT_ZDDIC_CRUD}/doma/${encodeURIComponent(p.name.toUpperCase())}`, {
    method:  "PUT",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    qs,
    body,
  });

  return ok(`✅ Domain '${p.name.toUpperCase()}' updated\n\n${JSON.stringify(resp, null, 2)}`);
}

// ── Data Element ──────────────────────────────────────────────────────────

export async function handleCreateDataElement(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_CreateDataElement.parse(args);
  assertPackageAllowed(p.devClass);
  assertCustomerNamespace(p.name, ["Z", "Y"]);

  const body = JSON.stringify({
    name:        p.name.toUpperCase(),
    description: p.description,
    domain:      p.domain.toUpperCase(),
    shortLabel:  p.shortLabel ?? "",
    mediumLabel: p.mediumLabel ?? "",
    longLabel:   p.longLabel ?? "",
    package:     p.devClass,
    transport:   p.transport ?? "",
  });

  const qs: Record<string, string> = {};
  if (p.transport) qs.corrNr = p.transport;

  const resp = await client.httpClient.request(`${ADT_ZDDIC_CRUD}/dtel`, {
    method:  "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    qs,
    body,
  });

  return ok(`✅ Data element '${p.name.toUpperCase()}' created\n\n${JSON.stringify(resp, null, 2)}`);
}

export async function handleUpdateDataElement(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_UpdateDataElement.parse(args);
  assertCustomerNamespace(p.name, ["Z", "Y"]);

  const body = JSON.stringify({
    description: p.description,
    domain:      p.domain?.toUpperCase(),
    shortLabel:  p.shortLabel,
    mediumLabel: p.mediumLabel,
    longLabel:   p.longLabel,
    package:     p.devClass ?? "",
    transport:   p.transport ?? "",
  });

  const qs: Record<string, string> = {};
  if (p.transport) qs.corrNr = p.transport;

  const resp = await client.httpClient.request(`${ADT_ZDDIC_CRUD}/dtel/${encodeURIComponent(p.name.toUpperCase())}`, {
    method:  "PUT",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    qs,
    body,
  });

  return ok(`✅ Data element '${p.name.toUpperCase()}' updated\n\n${JSON.stringify(resp, null, 2)}`);
}

// ── Structure ─────────────────────────────────────────────────────────────

export async function handleCreateStructure(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_CreateStructure.parse(args);
  assertPackageAllowed(p.devClass);
  assertCustomerNamespace(p.name, ["Z", "Y"]);

  const body = JSON.stringify({
    name:        p.name.toUpperCase(),
    description: p.description,
    fields:      p.fields ?? [],
    package:     p.devClass,
    transport:   p.transport ?? "",
  });

  const qs: Record<string, string> = {};
  if (p.transport) qs.corrNr = p.transport;

  const resp = await client.httpClient.request(`${ADT_ZDDIC_CRUD}/stru`, {
    method:  "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    qs,
    body,
  });

  return ok(`✅ Structure '${p.name.toUpperCase()}' created\n\n${JSON.stringify(resp, null, 2)}`);
}

export async function handleUpdateStructure(client: ADTClient, args: Record<string, unknown>): Promise<ToolResult> {
  assertWriteEnabled();
  const p = S_UpdateStructure.parse(args);
  assertCustomerNamespace(p.name, ["Z", "Y"]);

  const body = JSON.stringify({
    description: p.description,
    fields:      p.fields,
    package:     p.devClass ?? "",
    transport:   p.transport ?? "",
  });

  const qs: Record<string, string> = {};
  if (p.transport) qs.corrNr = p.transport;

  const resp = await client.httpClient.request(`${ADT_ZDDIC_CRUD}/stru/${encodeURIComponent(p.name.toUpperCase())}`, {
    method:  "PUT",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    qs,
    body,
  });

  return ok(`✅ Structure '${p.name.toUpperCase()}' updated\n\n${JSON.stringify(resp, null, 2)}`);
}
