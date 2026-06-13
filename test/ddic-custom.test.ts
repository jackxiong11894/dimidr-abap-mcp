import { describe, it, expect } from "vitest";
import { detectDdicObjectKind, normalizeDdIcOperation } from "../src/helpers/ddic-crud.js";
import { TOOL_CATEGORIES } from "../src/tools/tool-registry.js";

describe("custom DDIC CRUD integration", () => {
  it("detects DDIC object kinds from dynamic child nodes", () => {
    const xml = [
      `<?xml version="1.0" encoding="UTF-8"?>`,
      `<adtcore:object xmlns:adtcore="http://www.sap.com/adt/core">`,
      `  <adtcore:type>DTEL/DE</adtcore:type>`,
      `  <adtcore:children>`,
      `    <dTEL:dataElement xmlns:dTEL="http://www.sap.com/adt/ddic/dataelements">`,
      `      <dTEL:abapType typeName="CHAR" length="10" />`,
      `    </dTEL:dataElement>`,
      `  </adtcore:children>`,
      `</adtcore:object>`,
    ].join("\n");

    expect(detectDdicObjectKind(xml)).toBe("data_element");
  });

  it("normalizes custom DDIC operation names for the zddic_crud endpoint", () => {
    expect(normalizeDdIcOperation("read")).toBe("READ");
    expect(normalizeDdIcOperation("create_table")).toBe("CREATE");
    expect(normalizeDdIcOperation("delete_domain")).toBe("DELETE");
  });

  it("exposes the custom DDIC tool set in the registry", () => {
    expect(TOOL_CATEGORIES.DDIC).toContain("zddic_crud");
    expect(TOOL_CATEGORIES.DDIC).toContain("create_ddic_data_element");
  });
});
