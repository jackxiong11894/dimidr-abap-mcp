/**
 * Register the ICF service /sap/bc/zddic_crud programmatically.
 * Run with: npx tsx test-register-icf.ts
 */

import { config as dotenvConfig } from "dotenv";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

dotenvConfig({ path: resolve(dirname(fileURLToPath(import.meta.url)), ".env") });

const { getClient } = await import("./dist/adt-client.js");
const { session_types } = await import("abap-adt-api");

async function main() {
  console.log("🔌 Connecting to SAP...");
  const client = await getClient();
  console.log("✅ Connected!\n");

  // Create a temporary program to register the ICF service
  const progName = "Z_MCP_REG_ICF";
  const progUrl = `/sap/bc/adt/programs/programs/${progName.toLowerCase()}`;

  const source = `REPORT z_mcp_reg_icf.

DATA: lo_service TYPE REF TO if_icf_service,
      ls_icfserlnk TYPE icfserlnk,
      lt_icfserlnk TYPE TABLE OF icfserlnk,
      lv_url TYPE string,
      lv_handler TYPE string,
      lv_msg TYPE string.

* Check if service already exists
lv_url = '/sap/bc/zddic_crud'.
lv_handler = 'ZCL_ADT_DDIC_HANDLER'.

TRY.
    cl_icf_service=>get_service_by_url(
      EXPORTING
        url = lv_url
      IMPORTING
        service = lo_service ).
    IF lo_service IS BOUND.
      WRITE: / 'Service already exists:', lv_url.
    ENDIF.
  CATCH cx_icf_service.
    " Service doesn't exist, create it
    WRITE: / 'Service not found, creating...'.

    TRY.
        cl_icf_service=>create_service(
          EXPORTING
            url = lv_url
            handler_class = lv_handler
            description = 'DDIC CRUD Handler for MCP'
          IMPORTING
            service = lo_service ).
        WRITE: / 'Service created:', lo_service->get_url( ).

        " Activate the service
        lo_service->activate( ).
        WRITE: / 'Service activated!'.

      CATCH cx_icf_service INTO DATA(lx_err).
        WRITE: / 'Error creating service:', lx_err->get_text( ).
    ENDTRY.
ENDTRY.

* Alternative: direct table insert
IF lo_service IS NOT BOUND.
  WRITE: / 'Trying direct table insert...'.

  DATA: ls_node TYPE icfservice,
        ls_appl TYPE icfappl.

  " Check if already in table
  SELECT SINGLE icf_name FROM icfservice INTO ls_node-icf_name
    WHERE icf_name = 'zddic_crud' AND icfparguid = ''.
  IF sy-subrc <> 0.
    " Insert service node
    ls_node-icf_name = 'zddic_crud'.
    ls_node-icf_cuser = sy-uname.
    ls_node-icf_cdate = sy-datum.
    MODIFY icfservice FROM ls_node.
    WRITE: / 'Inserted into ICFSERVICE'.

    " Insert application handler
    ls_appl-icf_name = 'zddic_crud'.
    ls_appl-icf_applnm = 'ZCL_ADT_DDIC_HANDLER'.
    ls_appl-icf_cuser = sy-uname.
    ls_appl-icf_cdate = sy-datum.
    MODIFY icfappl FROM ls_appl.
    WRITE: / 'Inserted into ICFAPPL'.

    COMMIT WORK.
    WRITE: / 'Done! Service registered (may need SICF activation).'.
  ELSE.
    WRITE: / 'Already in ICFSERVICE table'.
  ENDIF.
ENDIF.`;

  // Create the program
  console.log("📦 Creating temporary program...");
  try {
    await client.createObject(
      "PROG/P", progName, "$TMP", "Register ICF Service",
      "/sap/bc/adt/packages/%24TMP", undefined, undefined
    );
    console.log("  ✅ Program created");
  } catch (e: any) {
    const msg = e.message || String(e);
    if (msg.includes("already exist") || msg.includes("SADT_RESOURCE")) {
      console.log("  ℹ️  Program already exists");
    } else {
      console.log("  ⚠️  Create:", msg.substring(0, 120));
    }
  }

  // Write source and execute
  console.log("📝 Writing source...");
  client.stateful = session_types.stateful;
  try {
    const lockResult = await client.lock(progUrl);
    const lockHandle = (lockResult as any)?.LOCK_HANDLE || (lockResult as any)?.lockHandle || "";
    await client.setObjectSource(`${progUrl}/source/main`, source, lockHandle);
    console.log("  ✅ Source written");

    // Activate
    await client.activate(progName, progUrl);
    console.log("  ✅ Activated");

    // Unlock
    await client.unLock(progUrl, lockHandle);
    console.log("  ✅ Unlocked");

    // Execute the program
    console.log("\n🚀 Executing ICF registration program...");
    const runResp = await client.httpClient.request(`${progUrl}/runs`, {
      method: "POST",
      headers: { "Content-Type": "application/xml" },
      body: `<?xml version="1.0" encoding="UTF-8"?`,
    });
    console.log("  ✅ Execution result:", JSON.stringify(runResp).substring(0, 500));

  } catch (e: any) {
    console.error("  ❌ Error:", e.message || String(e));
  } finally {
    try { await client.dropSession(); } catch {}
    client.stateful = session_types.stateless;
  }

  // Clean up: delete the temp program
  console.log("\n🧹 Cleaning up temp program...");
  try {
    await client.deleteObject(progUrl, undefined);
    console.log("  ✅ Deleted");
  } catch (e: any) {
    console.log("  ⚠️  Cleanup:", e.message?.substring(0, 120));
  }

  // Test the ICF service
  console.log("\n🧪 Testing ICF service...");
  try {
    const resp = await client.httpClient.request("/sap/bc/zddic_crud/doma/TEST", {
      method: "GET",
      headers: { Accept: "application/json" },
    });
    console.log("  ✅ ICF service responds:", JSON.stringify(resp).substring(0, 300));
  } catch (e: any) {
    console.log("  ❌ ICF service still not working:", e.message?.substring(0, 200));
    console.log("  📋 You may need to register the ICF service manually via SICF:");
    console.log("     Path: /sap/bc/zddic_crud");
    console.log("     Handler: ZCL_ADT_DDIC_HANDLER");
  }
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(1);
});
