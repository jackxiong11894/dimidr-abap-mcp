/**
 * Deploy ZCL_ADT_DDIC_HANDLER to SAP using proper stateful session.
 * Run with: npx tsx test-deploy.ts
 */

import { config as dotenvConfig } from "dotenv";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { readFileSync } from "fs";

dotenvConfig({ path: resolve(dirname(fileURLToPath(import.meta.url)), ".env") });

const { getClient } = await import("./dist/adt-client.js");
const { session_types } = await import("abap-adt-api");

async function main() {
  console.log("🔌 Connecting to SAP...");
  const client = await getClient();
  console.log("✅ Connected!\n");

  const classUrl = "/sap/bc/adt/oo/classes/zcl_adt_ddic_handler";
  const sourceUrl = `${classUrl}/source/main`;

  // Read ABAP source
  const abapSource = readFileSync(
    resolve(dirname(fileURLToPath(import.meta.url)), "src/abap/ZCL_ADT_DDIC_HANDLER.abap"),
    "utf-8"
  );

  // Step 1: Create class if it doesn't exist
  console.log("📦 Step 1: Ensure class exists...");
  try {
    await client.objectStructure(classUrl);
    console.log("  ℹ️  Class already exists");
  } catch {
    try {
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
      console.log("  ⚠️  Create:", e.message?.substring(0, 120));
    }
  }

  // Step 2: Write source in stateful mode
  console.log("\n📦 Step 2: Write source code...");
  try {
    // Switch to stateful mode for lock/write/activate
    client.stateful = session_types.stateful;

    // Lock
    console.log("  🔒 Locking...");
    const lockResult = await client.lock(classUrl);
    const lockHandle = (lockResult as any)?.LOCK_HANDLE || (lockResult as any)?.lockHandle || "";
    console.log(`  ✅ Locked (handle: ${lockHandle?.substring(0, 20)}...)`);

    // Write source
    console.log("  📝 Writing source...");
    await client.setObjectSource(sourceUrl, abapSource, lockHandle);
    console.log("  ✅ Source written");

    // Activate
    console.log("  ⚡ Activating...");
    const actResult = await client.activate("ZCL_ADT_DDIC_HANDLER", classUrl);
    console.log("  ✅ Activated");

    // Unlock
    console.log("  🔓 Unlocking...");
    await client.unLock(classUrl, lockHandle);
    console.log("  ✅ Unlocked");

    // Drop session and go back to stateless
    await client.dropSession();
    client.stateful = session_types.stateless;
  } catch (e: any) {
    console.error("  ❌ Error:", e.message || String(e));
    // Try to cleanup
    try { await client.unLock(classUrl, ""); } catch {}
    try { await client.dropSession(); } catch {}
    client.stateful = session_types.stateless;
  }

  // Step 3: Verify the class is active
  console.log("\n📦 Step 3: Verify class is active...");
  try {
    const source = await client.getObjectSource(sourceUrl);
    console.log(`  ✅ Class source readable (${source.length} chars)`);
  } catch (e: any) {
    console.log("  ❌ Cannot read class source:", e.message?.substring(0, 120));
  }

  // Step 4: Check if the ICF service exists
  console.log("\n📦 Step 4: Check ICF service /sap/bc/zddic_crud...");
  try {
    const resp = await client.httpClient.request("/sap/bc/zddic_crud", {
      method: "GET",
      headers: { Accept: "application/json" },
    });
    console.log("  ✅ ICF service responds:", JSON.stringify(resp).substring(0, 200));
  } catch (e: any) {
    const msg = e.message || String(e);
    if (msg.includes("404") || msg.includes("not found") || msg.includes("resource")) {
      console.log("  ⚠️  ICF service not found — you need to register it in SICF:");
      console.log("      1. Run SICF transaction");
      console.log("      2. Create service under /sap/bc/");
      console.log("      3. Service name: zddic_crud");
      console.log("      4. Handler class: ZCL_ADT_DDIC_HANDLER");
      console.log("      5. Activate the service");
    } else {
      console.log("  ❌ Error:", msg.substring(0, 200));
    }
  }

  console.log("\n🏁 Deployment complete!");
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(1);
});
