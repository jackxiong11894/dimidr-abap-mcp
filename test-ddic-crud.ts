/**
 * Quick smoke test for the DDIC CRUD tools.
 * Run with: npx tsx test-ddic-crud.ts
 *
 * Tests:
 * 1. Deploy ZCL_ADT_DDIC_HANDLER class to SAP
 * 2. Create a domain
 * 3. Read it back
 * 4. Create a data element
 * 5. Create a structure
 */

import { config as dotenvConfig } from "dotenv";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { readFileSync } from "fs";

dotenvConfig({ path: resolve(dirname(fileURLToPath(import.meta.url)), ".env") });

// Import after dotenv
const { getClient } = await import("./dist/adt-client.js");
const { ADT_ZDDIC_CRUD } = await import("./dist/adt-endpoints.js");

async function main() {
  console.log("🔌 Connecting to SAP...");
  const client = await getClient();
  console.log("✅ Connected!\n");

  // Step 1: Deploy ZCL_ADT_DDIC_HANDLER
  console.log("📦 Step 1: Deploying ZCL_ADT_DDIC_HANDLER...");
  const abapSource = readFileSync(
    resolve(dirname(fileURLToPath(import.meta.url)), "src/abap/ZCL_ADT_DDIC_HANDLER.abap"),
    "utf-8"
  );

  try {
    // Try to create the class first
    await client.createObject(
      "CLAS/OC",
      "ZCL_ADT_DDIC_HANDLER",
      "$TMP",
      "DDIC CRUD Handler for MCP",
      "/sap/bc/adt/packages/%24TMP",
      undefined,
      undefined
    );
    console.log("  ✅ Class created");
  } catch (e: any) {
    const msg = e.message || String(e);
    if (msg.includes("already exist") || msg.includes("SADT_RESOURCE")) {
      console.log("  ℹ️  Class already exists, will update source");
    } else {
      console.log("  ⚠️  Create error (may be OK):", msg.substring(0, 120));
    }
  }

  // Write source
  try {
    const lockResult = await client.lock("/sap/bc/adt/oo/classes/zcl_adt_ddic_handler");
    const lockHandle = (lockResult as any)?.LOCK_HANDLE || (lockResult as any)?.lockHandle;
    await client.setObjectSource(
      "/sap/bc/adt/oo/classes/zcl_adt_ddic_handler/source/main",
      abapSource,
      lockHandle
    );
    console.log("  ✅ Source written");

    // Syntax check
    const checkResult = await client.syntaxCheck(
      "/sap/bc/adt/oo/classes/zcl_adt_ddic_handler",
      "CLAS",
      abapSource
    );
    if (checkResult && checkResult.length > 0) {
      console.log("  ⚠️  Syntax warnings/errors:");
      for (const msg of checkResult) {
        console.log(`    [${(msg as any).type}] ${(msg as any).shortText}`);
      }
    } else {
      console.log("  ✅ Syntax check passed");
    }

    // Activate
    await client.activate("ZCL_ADT_DDIC_HANDLER", "/sap/bc/adt/oo/classes/zcl_adt_ddic_handler");
    console.log("  ✅ Class activated");

    // Unlock
    await client.unLock(
      "/sap/bc/adt/oo/classes/zcl_adt_ddic_handler",
      lockHandle
    );
    console.log("  ✅ Lock released\n");
  } catch (e: any) {
    console.error("  ❌ Error deploying class:", e.message || String(e));
    console.log("\n⚠️  Continuing with tests anyway (class may already be deployed)...\n");
  }

  // Step 2: Test the custom endpoint
  console.log("🧪 Step 2: Testing custom DDIC CRUD endpoint...");

  // Test: Create a domain
  console.log("\n  --- Create Domain ZDM_MCP_TEST_01 ---");
  try {
    const resp = await client.httpClient.request(`${ADT_ZDDIC_CRUD}/doma`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        name: "ZDM_MCP_TEST_01",
        description: "MCP Test Domain",
        datatype: "CHAR",
        length: 10,
        decimals: 0,
        package: "$TMP",
        transport: "",
      }),
    });
    console.log("  ✅ Response:", JSON.stringify(resp, null, 2));
  } catch (e: any) {
    console.log("  ❌ Error:", e.message || String(e));
  }

  // Test: Read domain back
  console.log("\n  --- Read Domain ZDM_MCP_TEST_01 ---");
  try {
    const resp = await client.httpClient.request(`${ADT_ZDDIC_CRUD}/doma/ZDM_MCP_TEST_01`, {
      method: "GET",
      headers: { Accept: "application/json" },
    });
    console.log("  ✅ Response:", JSON.stringify(resp, null, 2));
  } catch (e: any) {
    console.log("  ❌ Error:", e.message || String(e));
  }

  // Test: Create a data element
  console.log("\n  --- Create Data Element ZDE_MCP_TEST_01 ---");
  try {
    const resp = await client.httpClient.request(`${ADT_ZDDIC_CRUD}/dtel`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        name: "ZDE_MCP_TEST_01",
        description: "MCP Test Data Element",
        domain: "ZDM_MCP_TEST_01",
        shortLabel: "Test",
        mediumLabel: "Test Element",
        longLabel: "MCP Test Data Element",
        package: "$TMP",
        transport: "",
      }),
    });
    console.log("  ✅ Response:", JSON.stringify(resp, null, 2));
  } catch (e: any) {
    console.log("  ❌ Error:", e.message || String(e));
  }

  // Test: Create a structure
  console.log("\n  --- Create Structure ZST_MCP_TEST_01 ---");
  try {
    const resp = await client.httpClient.request(`${ADT_ZDDIC_CRUD}/stru`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        name: "ZST_MCP_TEST_01",
        description: "MCP Test Structure",
        fields: [
          { name: "FIELD1", rollname: "ZDE_MCP_TEST_01", key: true, description: "Key Field" },
          { name: "FIELD2", datatype: "CHAR", length: 20, description: "Char Field" },
        ],
        package: "$TMP",
        transport: "",
      }),
    });
    console.log("  ✅ Response:", JSON.stringify(resp, null, 2));
  } catch (e: any) {
    console.log("  ❌ Error:", e.message || String(e));
  }

  console.log("\n🏁 Tests complete!");
}

main().catch((e) => {
  console.error("Fatal error:", e);
  process.exit(1);
});
