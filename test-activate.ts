/**
 * Activate ZCL_ADT_DDIC_HANDLER and check ICF service.
 * Run with: npx tsx test-activate.ts
 */

import { config as dotenvConfig } from "dotenv";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

dotenvConfig({ path: resolve(dirname(fileURLToPath(import.meta.url)), ".env") });

const { getClient } = await import("./dist/adt-client.js");

async function main() {
  console.log("🔌 Connecting to SAP...");
  const client = await getClient();
  console.log("✅ Connected!\n");

  const classUrl = "/sap/bc/adt/oo/classes/zcl_adt_ddic_handler";

  // Drop any stale session
  try { await client.dropSession(); } catch {}

  // Try to activate
  console.log("⚡ Activating ZCL_ADT_DDIC_HANDLER...");
  try {
    await client.activate("ZCL_ADT_DDIC_HANDLER", classUrl);
    console.log("  ✅ Activated!");
  } catch (e: any) {
    const msg = e.message || String(e);
    if (msg.includes("currently editing")) {
      console.log("  ⚠️  Lock conflict — trying to unlock first...");
      try {
        await client.unLock(classUrl, "");
        await client.activate("ZCL_ADT_DDIC_HANDLER", classUrl);
        console.log("  ✅ Activated after unlock!");
      } catch (e2: any) {
        console.log("  ❌ Still failed:", e2.message?.substring(0, 200));
      }
    } else {
      console.log("  ❌ Error:", msg.substring(0, 200));
    }
  }

  // Check ICF service
  console.log("\n🔍 Checking ICF service /sap/bc/zddic_crud...");
  try {
    const resp = await client.httpClient.request("/sap/bc/zddic_crud/doma/TEST", {
      method: "GET",
      headers: { Accept: "application/json" },
    });
    console.log("  ✅ ICF service responds:", JSON.stringify(resp).substring(0, 200));
  } catch (e: any) {
    const msg = e.message || String(e);
    console.log("  ❌ ICF service error:", msg.substring(0, 200));

    if (msg.includes("500") || msg.includes("404") || msg.includes("not found")) {
      console.log("\n  📋 The ICF service /sap/bc/zddic_crud needs to be registered in SAP.");
      console.log("  Options:");
      console.log("  1. Run SICF → Create service under /sap/bc/ → name: zddic_crud");
      console.log("     Handler class: ZCL_ADT_DDIC_HANDLER → Activate");
      console.log("  2. Or use the ABAP snippet below to register it programmatically:\n");
      console.log(`  DATA: lo_server TYPE REF TO if_http_server.
  " Register via SICF or use CL_ICF_SERVICE=>CREATE_SERVICE
  " The service path must be: /sap/bc/zddic_crud
  " Handler list: ZCL_ADT_DDIC_HANDLER`);
    }
  }

  // Try reading the class source to verify it's properly deployed
  console.log("\n📖 Verifying class source...");
  try {
    const source = await client.getObjectSource(`${classUrl}/source/main`);
    const lines = source.split("\n").length;
    console.log(`  ✅ Source readable: ${lines} lines, ${source.length} chars`);

    // Check if it has the key methods
    const hasHandleRequest = source.includes("if_http_extension~handle_request");
    const hasHandleDomain = source.includes("handle_domain");
    const hasJsonDecode = source.includes("json_decode");
    console.log(`  Methods: handle_request=${hasHandleRequest}, handle_domain=${hasHandleDomain}, json_decode=${hasJsonDecode}`);
  } catch (e: any) {
    console.log("  ❌ Error:", e.message?.substring(0, 120));
  }
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(1);
});
