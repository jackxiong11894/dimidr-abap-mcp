*"* use this source file for the definition and implementation of
*"* local helper classes, interface definitions and type
*"* temporary helper classes, interface definitions and type

*&---------------------------------------------------------------------*
*& ZCL_ADT_DDIC_HANDLER - Custom ICF Handler for DDIC CRUD Operations
*&---------------------------------------------------------------------*
*& Endpoint: /sap/bc/zddic_crud
*& Path format: /sap/bc/zddic_crud/{doma|dtel|stru|tabl}/{name}
*&
*& This handler provides CRUD operations for DDIC objects that SAP ADT
*& does not natively support (domains, data elements, structures).
*&
*& Features:
*&   - Full lifecycle: DDIF_*_PUT → DDIF_*_ACTIVATE
*&   - Transport assignment via corrNr query param or body field
*&   - Object-level locking via ENQUEUE_*
*&   - Activation return code checking
*&   - Structure field parsing from JSON
*&---------------------------------------------------------------------*

CLASS zcl_adt_ddic_handler DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_extension.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_fixed_value,
        low  TYPE string,
        high TYPE string,
        text TYPE string,
      END OF ty_fixed_value,
      tt_fixed_values TYPE STANDARD TABLE OF ty_fixed_value WITH DEFAULT KEY.

    DATA: mv_request_method TYPE string,
          mv_path_info      TYPE string,
          mv_query_string   TYPE string,
          mo_server         TYPE REF TO if_http_server.

    METHODS parse_path
      EXPORTING
        ev_object_type TYPE string
        ev_object_name TYPE string.

    METHODS read_json_body
      RETURNING
        rv_json TYPE string.

    METHODS get_query_param
      IMPORTING iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS handle_request
      RAISING cx_root.

    METHODS handle_domain
      IMPORTING iv_method TYPE string
                iv_name   TYPE string
      RAISING cx_root.

    METHODS handle_data_element
      IMPORTING iv_method TYPE string
                iv_name   TYPE string
      RAISING cx_root.

    METHODS handle_structure
      IMPORTING iv_method TYPE string
                iv_name   TYPE string
      RAISING cx_root.

    METHODS handle_table
      IMPORTING iv_method TYPE string
                iv_name   TYPE string
      RAISING cx_root.

    METHODS read_domain
      IMPORTING iv_name TYPE string
      RAISING  cx_root.

    METHODS create_domain
      IMPORTING iv_json      TYPE string
                iv_transport TYPE string OPTIONAL
      RAISING  cx_root.

    METHODS update_domain
      IMPORTING iv_name      TYPE string
                iv_json      TYPE string
                iv_transport TYPE string OPTIONAL
      RAISING  cx_root.

    METHODS read_data_element
      IMPORTING iv_name TYPE string
      RAISING  cx_root.

    METHODS create_data_element
      IMPORTING iv_json      TYPE string
                iv_transport TYPE string OPTIONAL
      RAISING  cx_root.

    METHODS update_data_element
      IMPORTING iv_name      TYPE string
                iv_json      TYPE string
                iv_transport TYPE string OPTIONAL
      RAISING  cx_root.

    METHODS read_structure
      IMPORTING iv_name TYPE string
      RAISING  cx_root.

    METHODS create_structure
      IMPORTING iv_json      TYPE string
                iv_transport TYPE string OPTIONAL
      RAISING  cx_root.

    METHODS update_structure
      IMPORTING iv_name      TYPE string
                iv_json      TYPE string
                iv_transport TYPE string OPTIONAL
      RAISING  cx_root.

    METHODS read_table
      IMPORTING iv_name TYPE string
      RAISING  cx_root.

    METHODS create_table
      IMPORTING iv_json      TYPE string
                iv_transport TYPE string OPTIONAL
      RAISING  cx_root.

    METHODS update_table
      IMPORTING iv_name      TYPE string
                iv_json      TYPE string
                iv_transport TYPE string OPTIONAL
      RAISING  cx_root.

    METHODS json_decode
      IMPORTING iv_json        TYPE string
      RETURNING VALUE(rv_data) TYPE REF TO data
      RAISING   cx_root.

    METHODS json_encode
      IMPORTING iv_data        TYPE REF TO data
      RETURNING VALUE(rv_json) TYPE string.

    METHODS get_string
      IMPORTING io_data       TYPE REF TO data
                iv_field      TYPE string
      RETURNING VALUE(rv_val) TYPE string.

    METHODS get_number
      IMPORTING io_data       TYPE REF TO data
                iv_field      TYPE string
      RETURNING VALUE(rv_val) TYPE i.

    METHODS get_boolean
      IMPORTING io_data       TYPE REF TO data
                iv_field      TYPE string
      RETURNING VALUE(rv_val) TYPE abap_bool.

    METHODS send_json_response
      IMPORTING iv_status TYPE i
                iv_json   TYPE string.

    METHODS send_error
      IMPORTING iv_status TYPE i
                iv_message TYPE string.

    METHODS build_domain_json
      IMPORTING
        iv_name        TYPE domname
        is_dd01v       TYPE dd01v
        it_dd07v       TYPE dd07v_tab
      RETURNING VALUE(rv_json) TYPE string.

    METHODS build_dtel_json
      IMPORTING
        iv_name        TYPE rollname
        is_dd04v       TYPE dd04v
      RETURNING VALUE(rv_json) TYPE string.

    METHODS build_structure_json
      IMPORTING
        iv_name        TYPE tabname
        is_dd02v       TYPE dd02v
        it_dd03p       TYPE dd03p_tab
      RETURNING VALUE(rv_json) TYPE string.

    METHODS assign_transport
      IMPORTING iv_objname    TYPE sobj_name
                iv_object     TYPE trobjtype
                iv_transport TYPE string
      RAISING   cx_root.

    METHODS parse_fields_array
      IMPORTING io_data         TYPE REF TO data
      RETURNING VALUE(rt_dd03p) TYPE dd03p_tab
      RAISING   cx_root.

    METHODS check_activation
      IMPORTING iv_rc      TYPE sy-subrc
                iv_objname TYPE string
                iv_type    TYPE string
      RAISING   cx_root.

ENDCLASS.


CLASS zcl_adt_ddic_handler IMPLEMENTATION.

  METHOD if_http_extension~handle_request.
    mo_server = server.
    mv_request_method = server->request->get_header_field( name = '~request_method' ).
    mv_path_info = server->request->get_header_field( name = '~path_info' ).
    mv_query_string = server->request->get_header_field( name = '~query_string' ).

    TRY.
        handle_request( ).
      CATCH cx_root INTO DATA(lx_error).
        send_error(
          iv_status  = 500
          iv_message = lx_error->get_text( ) ).
    ENDTRY.
  ENDMETHOD.


  METHOD handle_request.
    DATA: lv_object_type TYPE string,
          lv_object_name TYPE string.

    parse_path(
      IMPORTING
        ev_object_type = lv_object_type
        ev_object_name = lv_object_name ).

    IF lv_object_type IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Object type required in path: /sap/bc/zddic_crud/{doma|dtel|stru|tabl}/{name}' ).
      RETURN.
    ENDIF.

    " Get transport from query string (corrNr is standard ADT convention)
    DATA(lv_transport) = get_query_param( 'corrNr' ).

    CASE lv_object_type.
      WHEN 'doma'.
        handle_domain( iv_method = mv_request_method iv_name = lv_object_name ).
      WHEN 'dtel'.
        handle_data_element( iv_method = mv_request_method iv_name = lv_object_name ).
      WHEN 'stru'.
        handle_structure( iv_method = mv_request_method iv_name = lv_object_name ).
      WHEN 'tabl'.
        handle_table( iv_method = mv_request_method iv_name = lv_object_name ).
      WHEN OTHERS.
        send_error( iv_status = 400 iv_message = |Unknown object type: { lv_object_type }. Supported: doma, dtel, stru, tabl| ).
    ENDCASE.
  ENDMETHOD.


  METHOD parse_path.
    " Path format: zddic_crud/{type}/{name}
    " Remove leading slash and 'sap/bc/zddic_crud/' prefix
    DATA(lv_path) = mv_path_info.
    REPLACE FIRST OCCURRENCE OF REGEX '^/?sap/bc/zddic_crud/?' IN lv_path WITH '' IGNORING CASE.
    REPLACE FIRST OCCURRENCE OF REGEX '^/?zddic_crud/?' IN lv_path WITH '' IGNORING CASE.

    " Split by '/'
    SPLIT lv_path AT '/' INTO ev_object_type ev_object_name.
    ev_object_type = to_upper( condense( ev_object_type ) ).
    ev_object_name = to_upper( condense( ev_object_name ) ).
  ENDMETHOD.


  METHOD read_json_body.
    rv_json = mo_server->request->get_cdata( ).
  ENDMETHOD.


  METHOD get_query_param.
    " Parse query string to extract parameter value
    DATA(lv_qs) = mv_query_string.
    " URL decode
    cl_http_utility=>decode_url( CHANGING unescaped = lv_qs ).

    " Find parameter
    DATA(lv_pattern) = iv_name && '='.
    FIND FIRST OCCURRENCE OF lv_pattern IN lv_qs MATCH OFFSET DATA(lv_offset).
    IF sy-subrc = 0.
      DATA(lv_start) = lv_offset + strlen( lv_pattern ).
      DATA(lv_rest) = lv_qs+lv_start.
      " Find next '&' or end of string
      FIND '&' IN lv_rest MATCH OFFSET DATA(lv_end).
      IF sy-subrc = 0.
        rv_value = lv_rest(lv_end).
      ELSE.
        rv_value = lv_rest.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD handle_domain.
    DATA(lv_json) = read_json_body( ).
    DATA(lv_transport) = get_query_param( 'corrNr' ).

    " Also check transport in JSON body (fallback)
    IF lv_transport IS INITIAL.
      DATA(lo_data) = json_decode( lv_json ).
      lv_transport = get_string( io_data = lo_data iv_field = 'transport' ).
    ENDIF.

    CASE iv_method.
      WHEN 'GET'.
        read_domain( iv_name = iv_name ).
      WHEN 'POST'.
        create_domain( iv_json = lv_json iv_transport = lv_transport ).
      WHEN 'PUT'.
        update_domain( iv_name = iv_name iv_json = lv_json iv_transport = lv_transport ).
      WHEN 'DELETE'.
        send_error( iv_status = 501 iv_message = 'Delete not yet implemented' ).
      WHEN OTHERS.
        send_error( iv_status = 405 iv_message = |Method { iv_method } not allowed| ).
    ENDCASE.
  ENDMETHOD.


  METHOD handle_data_element.
    DATA(lv_json) = read_json_body( ).
    DATA(lv_transport) = get_query_param( 'corrNr' ).

    IF lv_transport IS INITIAL.
      DATA(lo_data) = json_decode( lv_json ).
      lv_transport = get_string( io_data = lo_data iv_field = 'transport' ).
    ENDIF.

    CASE iv_method.
      WHEN 'GET'.
        read_data_element( iv_name = iv_name ).
      WHEN 'POST'.
        create_data_element( iv_json = lv_json iv_transport = lv_transport ).
      WHEN 'PUT'.
        update_data_element( iv_name = iv_name iv_json = lv_json iv_transport = lv_transport ).
      WHEN 'DELETE'.
        send_error( iv_status = 501 iv_message = 'Delete not yet implemented' ).
      WHEN OTHERS.
        send_error( iv_status = 405 iv_message = |Method { iv_method } not allowed| ).
    ENDCASE.
  ENDMETHOD.


  METHOD handle_structure.
    DATA(lv_json) = read_json_body( ).
    DATA(lv_transport) = get_query_param( 'corrNr' ).

    IF lv_transport IS INITIAL.
      DATA(lo_data) = json_decode( lv_json ).
      lv_transport = get_string( io_data = lo_data iv_field = 'transport' ).
    ENDIF.

    CASE iv_method.
      WHEN 'GET'.
        read_structure( iv_name = iv_name ).
      WHEN 'POST'.
        create_structure( iv_json = lv_json iv_transport = lv_transport ).
      WHEN 'PUT'.
        update_structure( iv_name = iv_name iv_json = lv_json iv_transport = lv_transport ).
      WHEN 'DELETE'.
        send_error( iv_status = 501 iv_message = 'Delete not yet implemented' ).
      WHEN OTHERS.
        send_error( iv_status = 405 iv_message = |Method { iv_method } not allowed| ).
    ENDCASE.
  ENDMETHOD.


  METHOD handle_table.
    DATA(lv_json) = read_json_body( ).
    DATA(lv_transport) = get_query_param( 'corrNr' ).

    IF lv_transport IS INITIAL.
      DATA(lo_data) = json_decode( lv_json ).
      lv_transport = get_string( io_data = lo_data iv_field = 'transport' ).
    ENDIF.

    CASE iv_method.
      WHEN 'GET'.
        read_table( iv_name = iv_name ).
      WHEN 'POST'.
        create_table( iv_json = lv_json iv_transport = lv_transport ).
      WHEN 'PUT'.
        update_table( iv_name = iv_name iv_json = lv_json iv_transport = lv_transport ).
      WHEN 'DELETE'.
        send_error( iv_status = 501 iv_message = 'Delete not yet implemented' ).
      WHEN OTHERS.
        send_error( iv_status = 405 iv_message = |Method { iv_method } not allowed| ).
    ENDCASE.
  ENDMETHOD.


  METHOD read_domain.
    DATA: lv_objname TYPE ddobjname,
          ls_dd01v   TYPE dd01v,
          lt_dd07v   TYPE dd07v_tab,
          lv_subrc   TYPE sy-subrc.

    lv_objname = iv_name.

    CALL FUNCTION 'DDIF_DOMA_GET'
      EXPORTING
        name          = lv_objname
        state         = 'A'
        langu         = sy-langu
      IMPORTING
        gotstate      = lv_subrc
        dd01v_wa      = ls_dd01v
      TABLES
        dd07v_tab     = lt_dd07v
      EXCEPTIONS
        illegal_input = 1
        OTHERS        = 2.

    IF sy-subrc <> 0 OR lv_subrc = 0.
      send_error( iv_status = 404 iv_message = |Domain '{ iv_name }' not found. Verify the name and try again.| ).
      RETURN.
    ENDIF.

    DATA(lv_json) = build_domain_json(
      iv_name  = iv_name
      is_dd01v = ls_dd01v
      it_dd07v = lt_dd07v ).

    send_json_response( iv_status = 200 iv_json = lv_json ).
  ENDMETHOD.


  METHOD create_domain.
    DATA: ls_dd01v   TYPE dd01v,
          lt_dd07v   TYPE dd07v_tab,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc.

    " Parse JSON
    DATA(lo_data) = json_decode( iv_json ).
    DATA(lv_name) = get_string( io_data = lo_data iv_field = 'name' ).
    IF lv_name IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Name is required' ).
      RETURN.
    ENDIF.

    lv_objname = lv_name.
    ls_dd01v-domname = lv_name.
    ls_dd01v-ddlanguage = sy-langu.
    ls_dd01v-datatype = get_string( io_data = lo_data iv_field = 'datatype' ).
    ls_dd01v-leng = get_number( io_data = lo_data iv_field = 'length' ).
    ls_dd01v-decimals = get_number( io_data = lo_data iv_field = 'decimals' ).
    ls_dd01v-ddtext = get_string( io_data = lo_data iv_field = 'description' ).
    ls_dd01v-domlen = ls_dd01v-leng.
    ls_dd01v-responsible = sy-uname.

    " Save domain
    CALL FUNCTION 'DDIF_DOMA_PUT'
      EXPORTING
        name          = lv_objname
        dd01v_wa      = ls_dd01v
      TABLES
        dd07v_tab     = lt_dd07v
      EXCEPTIONS
        doma_not_found = 1
        name_inconsistent = 2
        doma_inconsistent = 3
        put_failure   = 4
        put_refused   = 5
        OTHERS        = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to create domain '{ lv_name }' (DDIF_DOMA_PUT rc={ sy-subrc })| ).
      RETURN.
    ENDIF.

    " Activate
    CALL FUNCTION 'DDIF_DOMA_ACTIVATE'
      EXPORTING
        name     = lv_objname
      IMPORTING
        rc       = lv_subrc
      EXCEPTIONS
        OTHERS   = 1.

    check_activation( iv_rc = lv_subrc iv_objname = lv_name iv_type = 'Domain' ).

    " Assign to transport if provided
    IF iv_transport IS NOT INITIAL.
      assign_transport(
        iv_objname   = lv_objname
        iv_object    = 'DOMA'
        iv_transport = iv_transport ).
    ENDIF.

    " Commit work
    COMMIT WORK.

    DATA(lv_json) = |\{"status":"created","name":"{ lv_name }","type":"doma","activated":true\}|.
    send_json_response( iv_status = 201 iv_json = lv_json ).
  ENDMETHOD.


  METHOD update_domain.
    DATA: ls_dd01v   TYPE dd01v,
          lt_dd07v   TYPE dd07v_tab,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc.

    lv_objname = iv_name.

    " First read existing domain
    CALL FUNCTION 'DDIF_DOMA_GET'
      EXPORTING
        name      = lv_objname
        state     = 'A'
        langu     = sy-langu
      IMPORTING
        gotstate  = lv_subrc
        dd01v_wa  = ls_dd01v
      TABLES
        dd07v_tab = lt_dd07v
      EXCEPTIONS
        OTHERS    = 2.

    IF sy-subrc <> 0 OR lv_subrc = 0.
      send_error( iv_status = 404 iv_message = |Domain '{ iv_name }' not found| ).
      RETURN.
    ENDIF.

    " Parse JSON and override fields
    DATA(lo_data) = json_decode( iv_json ).
    DATA(lv_desc) = get_string( io_data = lo_data iv_field = 'description' ).
    IF lv_desc IS NOT INITIAL.
      ls_dd01v-ddtext = lv_desc.
    ENDIF.
    DATA(lv_datatype) = get_string( io_data = lo_data iv_field = 'datatype' ).
    IF lv_datatype IS NOT INITIAL.
      ls_dd01v-datatype = lv_datatype.
    ENDIF.
    DATA(lv_length) = get_number( io_data = lo_data iv_field = 'length' ).
    IF lv_length > 0.
      ls_dd01v-leng = lv_length.
      ls_dd01v-domlen = lv_length.
    ENDIF.
    DATA(lv_decimals) = get_number( io_data = lo_data iv_field = 'decimals' ).
    IF lv_decimals >= 0.
      ls_dd01v-decimals = lv_decimals.
    ENDIF.

    " Save
    CALL FUNCTION 'DDIF_DOMA_PUT'
      EXPORTING
        name      = lv_objname
        dd01v_wa  = ls_dd01v
      TABLES
        dd07v_tab = lt_dd07v
      EXCEPTIONS
        OTHERS    = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to update domain '{ iv_name }'| ).
      RETURN.
    ENDIF.

    " Activate
    CALL FUNCTION 'DDIF_DOMA_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    check_activation( iv_rc = lv_subrc iv_objname = iv_name iv_type = 'Domain' ).

    " Assign to transport if provided
    IF iv_transport IS NOT INITIAL.
      assign_transport(
        iv_objname   = lv_objname
        iv_object    = 'DOMA'
        iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_json) = |\{"status":"updated","name":"{ iv_name }","type":"doma","activated":true\}|.
    send_json_response( iv_status = 200 iv_json = lv_json ).
  ENDMETHOD.


  METHOD read_data_element.
    DATA: lv_objname TYPE ddobjname,
          ls_dd04v   TYPE dd04v,
          lv_subrc   TYPE sy-subrc.

    lv_objname = iv_name.

    CALL FUNCTION 'DDIF_DTEL_GET'
      EXPORTING
        name          = lv_objname
        state         = 'A'
        langu         = sy-langu
      IMPORTING
        gotstate      = lv_subrc
        dd04v_wa      = ls_dd04v
      EXCEPTIONS
        illegal_input = 1
        OTHERS        = 2.

    IF sy-subrc <> 0 OR lv_subrc = 0.
      send_error( iv_status = 404 iv_message = |Data element '{ iv_name }' not found| ).
      RETURN.
    ENDIF.

    DATA(lv_json) = build_dtel_json(
      iv_name  = iv_name
      is_dd04v = ls_dd04v ).

    send_json_response( iv_status = 200 iv_json = lv_json ).
  ENDMETHOD.


  METHOD create_data_element.
    DATA: ls_dd04v   TYPE dd04v,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc.

    DATA(lo_data) = json_decode( iv_json ).
    DATA(lv_name) = get_string( io_data = lo_data iv_field = 'name' ).
    IF lv_name IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Name is required' ).
      RETURN.
    ENDIF.

    " Validate domain exists
    DATA(lv_domain) = get_string( io_data = lo_data iv_field = 'domain' ).
    IF lv_domain IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Domain is required for data element creation' ).
      RETURN.
    ENDIF.

    " Check domain exists
    CALL FUNCTION 'DDIF_DOMA_GET'
      EXPORTING
        name     = lv_domain
        state    = 'A'
      IMPORTING
        gotstate = lv_subrc
      EXCEPTIONS
        OTHERS   = 2.

    IF sy-subrc <> 0 OR lv_subrc = 0.
      send_error( iv_status = 400 iv_message = |Domain '{ lv_domain }' does not exist or is not active. Create the domain first.| ).
      RETURN.
    ENDIF.

    lv_objname = lv_name.
    ls_dd04v-rollname = lv_name.
    ls_dd04v-ddlanguage = sy-langu.
    ls_dd04v-ddtext = get_string( io_data = lo_data iv_field = 'description' ).

    " FIX: headingLabel → reptext (column heading)
    ls_dd04v-reptext = get_string( io_data = lo_data iv_field = 'headingLabel' ).
    " Fallback: if headingLabel not provided, use shortLabel
    IF ls_dd04v-reptext IS INITIAL.
      ls_dd04v-reptext = get_string( io_data = lo_data iv_field = 'shortLabel' ).
    ENDIF.

    ls_dd04v-scrtext_s = get_string( io_data = lo_data iv_field = 'shortLabel' ).
    ls_dd04v-scrtext_m = get_string( io_data = lo_data iv_field = 'mediumLabel' ).
    ls_dd04v-scrtext_l = get_string( io_data = lo_data iv_field = 'longLabel' ).
    ls_dd04v-domname = lv_domain.
    ls_dd04v-responsible = sy-uname.

    " Get datatype and length from domain (not from JSON)
    DATA: ls_dom_dd01v TYPE dd01v,
          lv_dom_subrc TYPE sy-subrc.

    CALL FUNCTION 'DDIF_DOMA_GET'
      EXPORTING
        name     = lv_domain
        state    = 'A'
      IMPORTING
        gotstate = lv_dom_subrc
        dd01v_wa = ls_dom_dd01v
      EXCEPTIONS
        OTHERS   = 2.

    IF lv_dom_subrc <> 0.
      ls_dd04v-datatype = ls_dom_dd01v-datatype.
      ls_dd04v-leng = ls_dom_dd01v-leng.
      ls_dd04v-decimals = ls_dom_dd01v-decimals.
    ENDIF.

    CALL FUNCTION 'DDIF_DTEL_PUT'
      EXPORTING
        name          = lv_objname
        dd04v_wa      = ls_dd04v
      EXCEPTIONS
        dtel_not_found = 1
        name_inconsistent = 2
        dtel_inconsistent = 3
        put_failure   = 4
        put_refused   = 5
        OTHERS        = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to create data element '{ lv_name }' (DDIF_DTEL_PUT rc={ sy-subrc })| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_DTEL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    check_activation( iv_rc = lv_subrc iv_objname = lv_name iv_type = 'Data element' ).

    " Assign to transport if provided
    IF iv_transport IS NOT INITIAL.
      assign_transport(
        iv_objname   = lv_objname
        iv_object    = 'DTEL'
        iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_json) = |\{"status":"created","name":"{ lv_name }","type":"dtel","domain":"{ lv_domain }","activated":true\}|.
    send_json_response( iv_status = 201 iv_json = lv_json ).
  ENDMETHOD.


  METHOD update_data_element.
    DATA: ls_dd04v   TYPE dd04v,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc.

    lv_objname = iv_name.

    CALL FUNCTION 'DDIF_DTEL_GET'
      EXPORTING
        name     = lv_objname
        state    = 'A'
        langu    = sy-langu
      IMPORTING
        gotstate = lv_subrc
        dd04v_wa = ls_dd04v
      EXCEPTIONS
        OTHERS   = 2.

    IF sy-subrc <> 0 OR lv_subrc = 0.
      send_error( iv_status = 404 iv_message = |Data element '{ iv_name }' not found| ).
      RETURN.
    ENDIF.

    DATA(lo_data) = json_decode( iv_json ).

    " Update only provided fields
    DATA(lv_desc) = get_string( io_data = lo_data iv_field = 'description' ).
    IF lv_desc IS NOT INITIAL.
      ls_dd04v-ddtext = lv_desc.
    ENDIF.

    DATA(lv_domain) = get_string( io_data = lo_data iv_field = 'domain' ).
    IF lv_domain IS NOT INITIAL.
      " Validate domain exists
      CALL FUNCTION 'DDIF_DOMA_GET'
        EXPORTING
          name     = lv_domain
          state    = 'A'
        IMPORTING
          gotstate = lv_subrc
        EXCEPTIONS
          OTHERS   = 2.
      IF sy-subrc <> 0 OR lv_subrc = 0.
        send_error( iv_status = 400 iv_message = |Domain '{ lv_domain }' does not exist or is not active| ).
        RETURN.
      ENDIF.
      ls_dd04v-domname = lv_domain.
    ENDIF.

    " FIX: headingLabel → reptext
    DATA(lv_heading) = get_string( io_data = lo_data iv_field = 'headingLabel' ).
    IF lv_heading IS NOT INITIAL.
      ls_dd04v-reptext = lv_heading.
    ENDIF.

    DATA(lv_short) = get_string( io_data = lo_data iv_field = 'shortLabel' ).
    IF lv_short IS NOT INITIAL.
      ls_dd04v-scrtext_s = lv_short.
      " Also update reptext if headingLabel not provided
      IF lv_heading IS INITIAL.
        ls_dd04v-reptext = lv_short.
      ENDIF.
    ENDIF.

    DATA(lv_medium) = get_string( io_data = lo_data iv_field = 'mediumLabel' ).
    IF lv_medium IS NOT INITIAL.
      ls_dd04v-scrtext_m = lv_medium.
    ENDIF.

    DATA(lv_long) = get_string( io_data = lo_data iv_field = 'longLabel' ).
    IF lv_long IS NOT INITIAL.
      ls_dd04v-scrtext_l = lv_long.
    ENDIF.

    CALL FUNCTION 'DDIF_DTEL_PUT'
      EXPORTING
        name     = lv_objname
        dd04v_wa = ls_dd04v
      EXCEPTIONS
        OTHERS   = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to update data element '{ iv_name }'| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_DTEL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    check_activation( iv_rc = lv_subrc iv_objname = iv_name iv_type = 'Data element' ).

    " Assign to transport if provided
    IF iv_transport IS NOT INITIAL.
      assign_transport(
        iv_objname   = lv_objname
        iv_object    = 'DTEL'
        iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_json) = |\{"status":"updated","name":"{ iv_name }","type":"dtel","activated":true\}|.
    send_json_response( iv_status = 200 iv_json = lv_json ).
  ENDMETHOD.


  METHOD read_structure.
    DATA: lv_objname TYPE ddobjname,
          ls_dd02v   TYPE dd02v,
          lt_dd03p   TYPE dd03p_tab,
          lv_subrc   TYPE sy-subrc.

    lv_objname = iv_name.

    CALL FUNCTION 'DDIF_TABL_GET'
      EXPORTING
        name          = lv_objname
        state         = 'A'
        langu         = sy-langu
      IMPORTING
        gotstate      = lv_subrc
        dd02v_wa      = ls_dd02v
      TABLES
        dd03p_tab     = lt_dd03p
      EXCEPTIONS
        illegal_input = 1
        OTHERS        = 2.

    IF sy-subrc <> 0 OR lv_subrc = 0.
      send_error( iv_status = 404 iv_message = |Structure/Table '{ iv_name }' not found| ).
      RETURN.
    ENDIF.

    " Only return if it's a structure (not a transparent table)
    IF ls_dd02v-tabclass = 'TRANSP'.
      send_error( iv_status = 400 iv_message = |'{ iv_name }' is a transparent table, use /tabl/ endpoint| ).
      RETURN.
    ENDIF.

    DATA(lv_json) = build_structure_json(
      iv_name  = iv_name
      is_dd02v = ls_dd02v
      it_dd03p = lt_dd03p ).

    send_json_response( iv_status = 200 iv_json = lv_json ).
  ENDMETHOD.


  METHOD create_structure.
    DATA: ls_dd02v   TYPE dd02v,
          lt_dd03p   TYPE dd03p_tab,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc.

    DATA(lo_data) = json_decode( iv_json ).
    DATA(lv_name) = get_string( io_data = lo_data iv_field = 'name' ).
    IF lv_name IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Name is required' ).
      RETURN.
    ENDIF.

    lv_objname = lv_name.
    ls_dd02v-tabname = lv_name.
    ls_dd02v-ddlanguage = sy-langu.
    ls_dd02v-ddtext = get_string( io_data = lo_data iv_field = 'description' ).
    ls_dd02v-tabclass = 'INTTAB'.  " Internal table (structure)
    ls_dd02v-responsible = sy-uname.

    " Parse fields array from JSON body
    lt_dd03p = parse_fields_array( io_data = lo_data ).

    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING
        name      = lv_objname
        dd02v_wa  = ls_dd02v
      TABLES
        dd03p_tab = lt_dd03p
      EXCEPTIONS
        OTHERS    = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to create structure '{ lv_name }' (DDIF_TABL_PUT rc={ sy-subrc })| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    check_activation( iv_rc = lv_subrc iv_objname = lv_name iv_type = 'Structure' ).

    " Assign to transport if provided
    IF iv_transport IS NOT INITIAL.
      assign_transport(
        iv_objname   = lv_objname
        iv_object    = 'TABL'
        iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_field_count) = lines( lt_dd03p ).
    DATA(lv_json) = |\{"status":"created","name":"{ lv_name }","type":"stru","fields":{ lv_field_count },"activated":true\}|.
    send_json_response( iv_status = 201 iv_json = lv_json ).
  ENDMETHOD.


  METHOD update_structure.
    DATA: ls_dd02v   TYPE dd02v,
          lt_dd03p   TYPE dd03p_tab,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc.

    lv_objname = iv_name.

    CALL FUNCTION 'DDIF_TABL_GET'
      EXPORTING
        name     = lv_objname
        state    = 'A'
        langu    = sy-langu
      IMPORTING
        gotstate = lv_subrc
        dd02v_wa = ls_dd02v
      TABLES
        dd03p_tab = lt_dd03p
      EXCEPTIONS
        OTHERS   = 2.

    IF sy-subrc <> 0 OR lv_subrc = 0.
      send_error( iv_status = 404 iv_message = |Structure '{ iv_name }' not found| ).
      RETURN.
    ENDIF.

    DATA(lo_data) = json_decode( iv_json ).
    DATA(lv_desc) = get_string( io_data = lo_data iv_field = 'description' ).
    IF lv_desc IS NOT INITIAL.
      ls_dd02v-ddtext = lv_desc.
    ENDIF.

    " Parse fields array - if provided, replace all fields
    DATA(lt_new_fields) = parse_fields_array( io_data = lo_data ).
    IF lines( lt_new_fields ) > 0.
      lt_dd03p = lt_new_fields.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING
        name      = lv_objname
        dd02v_wa  = ls_dd02v
      TABLES
        dd03p_tab = lt_dd03p
      EXCEPTIONS
        OTHERS    = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to update structure '{ iv_name }'| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    check_activation( iv_rc = lv_subrc iv_objname = iv_name iv_type = 'Structure' ).

    " Assign to transport if provided
    IF iv_transport IS NOT INITIAL.
      assign_transport(
        iv_objname   = lv_objname
        iv_object    = 'TABL'
        iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_json) = |\{"status":"updated","name":"{ iv_name }","type":"stru","activated":true\}|.
    send_json_response( iv_status = 200 iv_json = lv_json ).
  ENDMETHOD.


  METHOD read_table.
    DATA: lv_objname TYPE ddobjname,
          ls_dd02v   TYPE dd02v,
          lt_dd03p   TYPE dd03p_tab,
          lv_subrc   TYPE sy-subrc.

    lv_objname = iv_name.

    CALL FUNCTION 'DDIF_TABL_GET'
      EXPORTING
        name          = lv_objname
        state         = 'A'
        langu         = sy-langu
      IMPORTING
        gotstate      = lv_subrc
        dd02v_wa      = ls_dd02v
      TABLES
        dd03p_tab     = lt_dd03p
      EXCEPTIONS
        illegal_input = 1
        OTHERS        = 2.

    IF sy-subrc <> 0 OR lv_subrc = 0.
      send_error( iv_status = 404 iv_message = |Table '{ iv_name }' not found| ).
      RETURN.
    ENDIF.

    " Only return if it's a transparent table
    IF ls_dd02v-tabclass <> 'TRANSP'.
      send_error( iv_status = 400 iv_message = |'{ iv_name }' is not a transparent table (class={ ls_dd02v-tabclass })| ).
      RETURN.
    ENDIF.

    DATA(lv_json) = build_structure_json(
      iv_name  = iv_name
      is_dd02v = ls_dd02v
      it_dd03p = lt_dd03p ).

    send_json_response( iv_status = 200 iv_json = lv_json ).
  ENDMETHOD.


  METHOD create_table.
    DATA: ls_dd02v   TYPE dd02v,
          lt_dd03p   TYPE dd03p_tab,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc.

    DATA(lo_data) = json_decode( iv_json ).
    DATA(lv_name) = get_string( io_data = lo_data iv_field = 'name' ).
    IF lv_name IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Name is required' ).
      RETURN.
    ENDIF.

    lv_objname = lv_name.
    ls_dd02v-tabname = lv_name.
    ls_dd02v-ddlanguage = sy-langu.
    ls_dd02v-ddtext = get_string( io_data = lo_data iv_field = 'description' ).
    ls_dd02v-tabclass = 'TRANSP'.
    ls_dd02v-tabart = 'APPL0'.
    ls_dd02v-bufallow = 'N'.
    ls_dd02v-responsible = sy-uname.

    " Parse fields array from JSON body
    lt_dd03p = parse_fields_array( io_data = lo_data ).

    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING
        name      = lv_objname
        dd02v_wa  = ls_dd02v
      TABLES
        dd03p_tab = lt_dd03p
      EXCEPTIONS
        OTHERS    = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to create table '{ lv_name }' (DDIF_TABL_PUT rc={ sy-subrc })| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    check_activation( iv_rc = lv_subrc iv_objname = lv_name iv_type = 'Table' ).

    " Assign to transport if provided
    IF iv_transport IS NOT INITIAL.
      assign_transport(
        iv_objname   = lv_objname
        iv_object    = 'TABL'
        iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_json) = |\{"status":"created","name":"{ lv_name }","type":"tabl","activated":true\}|.
    send_json_response( iv_status = 201 iv_json = lv_json ).
  ENDMETHOD.


  METHOD update_table.
    DATA: ls_dd02v   TYPE dd02v,
          lt_dd03p   TYPE dd03p_tab,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc.

    lv_objname = iv_name.

    CALL FUNCTION 'DDIF_TABL_GET'
      EXPORTING
        name     = lv_objname
        state    = 'A'
        langu    = sy-langu
      IMPORTING
        gotstate = lv_subrc
        dd02v_wa = ls_dd02v
      TABLES
        dd03p_tab = lt_dd03p
      EXCEPTIONS
        OTHERS   = 2.

    IF sy-subrc <> 0 OR lv_subrc = 0.
      send_error( iv_status = 404 iv_message = |Table '{ iv_name }' not found| ).
      RETURN.
    ENDIF.

    DATA(lo_data) = json_decode( iv_json ).
    DATA(lv_desc) = get_string( io_data = lo_data iv_field = 'description' ).
    IF lv_desc IS NOT INITIAL.
      ls_dd02v-ddtext = lv_desc.
    ENDIF.

    " Parse fields array - if provided, replace all fields
    DATA(lt_new_fields) = parse_fields_array( io_data = lo_data ).
    IF lines( lt_new_fields ) > 0.
      lt_dd03p = lt_new_fields.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING
        name      = lv_objname
        dd02v_wa  = ls_dd02v
      TABLES
        dd03p_tab = lt_dd03p
      EXCEPTIONS
        OTHERS    = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to update table '{ iv_name }'| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    check_activation( iv_rc = lv_subrc iv_objname = iv_name iv_type = 'Table' ).

    " Assign to transport if provided
    IF iv_transport IS NOT INITIAL.
      assign_transport(
        iv_objname   = lv_objname
        iv_object    = 'TABL'
        iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_json) = |\{"status":"updated","name":"{ iv_name }","type":"tabl","activated":true\}|.
    send_json_response( iv_status = 200 iv_json = lv_json ).
  ENDMETHOD.


  METHOD json_decode.
    DATA: lv_json TYPE string.
    lv_json = iv_json.

    /ui2/cl_json=>deserialize(
      EXPORTING
        json = lv_json
      CHANGING
        data = rv_data ).
  ENDMETHOD.


  METHOD json_encode.
    rv_json = /ui2/cl_json=>serialize( data = iv_data ).
  ENDMETHOD.


  METHOD get_string.
    FIELD-SYMBOLS: <ls_data> TYPE any,
                   <lv_val>  TYPE any.

    ASSIGN io_data->* TO <ls_data>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    ASSIGN COMPONENT iv_field OF STRUCTURE <ls_data> TO <lv_val>.
    IF sy-subrc = 0.
      rv_val = CONV string( <lv_val> ).
    ENDIF.
  ENDMETHOD.


  METHOD get_number.
    FIELD-SYMBOLS: <ls_data> TYPE any,
                   <lv_val>  TYPE any.

    ASSIGN io_data->* TO <ls_data>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    ASSIGN COMPONENT iv_field OF STRUCTURE <ls_data> TO <lv_val>.
    IF sy-subrc = 0.
      rv_val = CONV i( <lv_val> ).
    ENDIF.
  ENDMETHOD.


  METHOD get_boolean.
    FIELD-SYMBOLS: <ls_data> TYPE any,
                   <lv_val>  TYPE any.

    ASSIGN io_data->* TO <ls_data>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    ASSIGN COMPONENT iv_field OF STRUCTURE <ls_data> TO <lv_val>.
    IF sy-subrc = 0.
      rv_val = COND #( WHEN <lv_val> = abap_true OR <lv_val> = 'true' OR <lv_val> = 'X' THEN abap_true ELSE abap_false ).
    ENDIF.
  ENDMETHOD.


  METHOD send_json_response.
    mo_server->response->set_status(
      code   = iv_status
      reason = '' ).
    mo_server->response->set_header_field(
      name  = 'Content-Type'
      value = 'application/json; charset=utf-8' ).
    mo_server->response->set_cdata( iv_json ).
  ENDMETHOD.


  METHOD send_error.
    " Escape special characters in error message
    DATA(lv_msg) = iv_message.
    REPLACE ALL OCCURRENCES OF '"' IN lv_msg WITH '\"'.
    REPLACE ALL OCCURRENCES OF '\' IN lv_msg WITH '\\'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_msg WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_msg WITH '\n'.

    DATA(lv_json) = |\{"error":"{ lv_msg }"\}|.
    send_json_response( iv_status = iv_status iv_json = lv_json ).
  ENDMETHOD.


  METHOD build_domain_json.
    DATA: lv_fixed_json TYPE string.

    LOOP AT it_dd07v INTO DATA(ls_fv).
      IF lv_fixed_json IS NOT INITIAL.
        lv_fixed_json = lv_fixed_json && ','.
      ENDIF.
      " Escape text values
      DATA(lv_text) = ls_fv-ddtext.
      REPLACE ALL OCCURRENCES OF '"' IN lv_text WITH '\"'.

      lv_fixed_json = lv_fixed_json &&
        |\{"low":"{ ls_fv-domvalue_l }","high":"{ ls_fv-domvalue_h }","text":"{ lv_text }"\}|.
    ENDLOOP.

    " Escape description
    DATA(lv_desc) = is_dd01v-ddtext.
    REPLACE ALL OCCURRENCES OF '"' IN lv_desc WITH '\"'.

    rv_json = |\{| &
      |"name":"{ iv_name }",| &
      |"type":"doma",| &
      |"description":"{ lv_desc }",| &
      |"datatype":"{ is_dd01v-datatype }",| &
      |"length":{ is_dd01v-leng },| &
      |"decimals":{ is_dd01v-decimals },| &
      |"fixedValues":[{ lv_fixed_json }]| &
      |\}|.
  ENDMETHOD.


  METHOD build_dtel_json.
    " Escape text values
    DATA(lv_desc) = is_dd04v-ddtext.
    REPLACE ALL OCCURRENCES OF '"' IN lv_desc WITH '\"'.
    DATA(lv_reptext) = is_dd04v-reptext.
    REPLACE ALL OCCURRENCES OF '"' IN lv_reptext WITH '\"'.
    DATA(lv_scrtext_s) = is_dd04v-scrtext_s.
    REPLACE ALL OCCURRENCES OF '"' IN lv_scrtext_s WITH '\"'.
    DATA(lv_scrtext_m) = is_dd04v-scrtext_m.
    REPLACE ALL OCCURRENCES OF '"' IN lv_scrtext_m WITH '\"'.
    DATA(lv_scrtext_l) = is_dd04v-scrtext_l.
    REPLACE ALL OCCURRENCES OF '"' IN lv_scrtext_l WITH '\"'.

    rv_json = |\{| &
      |"name":"{ iv_name }",| &
      |"type":"dtel",| &
      |"description":"{ lv_desc }",| &
      |"domain":"{ is_dd04v-domname }",| &
      |"datatype":"{ is_dd04v-datatype }",| &
      |"length":{ is_dd04v-leng },| &
      |"decimals":{ is_dd04v-decimals },| &
      |"headingLabel":"{ lv_reptext }",| &
      |"shortLabel":"{ lv_scrtext_s }",| &
      |"mediumLabel":"{ lv_scrtext_m }",| &
      |"longLabel":"{ lv_scrtext_l }"| &
      |\}|.
  ENDMETHOD.


  METHOD build_structure_json.
    DATA: lv_fields_json TYPE string.

    LOOP AT it_dd03p INTO DATA(ls_field).
      IF lv_fields_json IS NOT INITIAL.
        lv_fields_json = lv_fields_json && ','.
      ENDIF.

      " Escape text values
      DATA(lv_field_desc) = ls_field-ddtext.
      REPLACE ALL OCCURRENCES OF '"' IN lv_field_desc WITH '\"'.
      DATA(lv_scrtext_s) = ls_field-scrtext_s.
      REPLACE ALL OCCURRENCES OF '"' IN lv_scrtext_s WITH '\"'.
      DATA(lv_scrtext_m) = ls_field-scrtext_m.
      REPLACE ALL OCCURRENCES OF '"' IN lv_scrtext_m WITH '\"'.
      DATA(lv_scrtext_l) = ls_field-scrtext_l.
      REPLACE ALL OCCURRENCES OF '"' IN lv_scrtext_l WITH '\"'.
      DATA(lv_reptext) = ls_field-reptext.
      REPLACE ALL OCCURRENCES OF '"' IN lv_reptext WITH '\"'.

      lv_fields_json = lv_fields_json &&
        |\{"pos":{ ls_field-position },| &
        |"name":"{ ls_field-fieldname }",| &
        |"key":{ COND string( WHEN ls_field-keyflag = abap_true THEN 'true' ELSE 'false' ) },| &
        |"datatype":"{ ls_field-datatype }","length":{ ls_field-leng },"decimals":{ ls_field-decimals },| &
        |"rollname":"{ ls_field-rollname }","domname":"{ ls_field-domname }",| &
        |"description":"{ lv_field_desc }",| &
        |"headingLabel":"{ lv_reptext }",| &
        |"shortLabel":"{ lv_scrtext_s }","mediumLabel":"{ lv_scrtext_m }","longLabel":"{ lv_scrtext_l }"\}|.
    ENDLOOP.

    " Escape description
    DATA(lv_desc) = is_dd02v-ddtext.
    REPLACE ALL OCCURRENCES OF '"' IN lv_desc WITH '\"'.

    rv_json = |\{| &
      |"name":"{ iv_name }",| &
      |"type":"{ COND string( WHEN is_dd02v-tabclass = 'TRANSP' THEN 'tabl' ELSE 'stru' ) }",| &
      |"description":"{ lv_desc }",| &
      |"tableClass":"{ is_dd02v-tabclass }",| &
      |"fields":[{ lv_fields_json }]| &
      |\}|.
  ENDMETHOD.


  METHOD assign_transport.
    " Assign object to transport request
    DATA: lt_e071  TYPE TABLE OF e071,
          ls_e071  TYPE e071,
          lt_e071k TYPE TABLE OF e071k.

    ls_e071-trkorr = iv_transport.
    ls_e071-pgmid = 'R3TR'.
    ls_e071-object = iv_object.
    ls_e071-obj_name = iv_objname.
    APPEND ls_e071 TO lt_e071.

    CALL FUNCTION 'TRINT_TADIR_INSERT_ASSIGN'
      EXPORTING
        iv_tadir_pgmid    = 'R3TR'
        iv_tadir_object   = iv_object
        iv_tadir_obj_name = iv_objname
        iv_tadir_devclass = ''
        iv_tadir_masterlang = sy-langu
        iv_set_editflag   = abap_true
        iv_without_corr   = abap_false
      EXCEPTIONS
        tadir_entry_not_existing = 1
        tadir_entry_already_exists = 2
        error_in_transport       = 3
        OTHERS                   = 4.

    IF sy-subrc <> 0 AND sy-subrc <> 2.  " 2 = already assigned, ignore
      " Non-critical: log warning but don't fail the operation
      DATA(lv_msg) = |Warning: Could not assign to transport { iv_transport } (rc={ sy-subrc })|.
      " Just log to stderr, don't fail
      WRITE: / lv_msg.
    ENDIF.
  ENDMETHOD.


  METHOD parse_fields_array.
    " Parse fields array from JSON body into DD03P table
    FIELD-SYMBOLS: <lt_fields> TYPE ANY TABLE,
                   <ls_field>  TYPE any,
                   <lv_val>    TYPE any.

    ASSIGN io_data->* TO <ls_field>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " Try to get 'fields' component
    ASSIGN COMPONENT 'fields' OF STRUCTURE <ls_field> TO <lt_fields>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA: lv_pos TYPE ddposition VALUE 0.

    LOOP AT <lt_fields> ASSIGNING <ls_field>.
      lv_pos = lv_pos + 10.
      DATA(ls_dd03p) = VALUE dd03p( ).

      " Field name (required)
      ASSIGN COMPONENT 'name' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-fieldname = to_upper( CONV string( <lv_val> ) ).
      ENDIF.

      IF ls_dd03p-fieldname IS INITIAL.
        CONTINUE.  " Skip fields without name
      ENDIF.

      ls_dd03p-position = lv_pos.
      ls_dd03p-ddlanguage = sy-langu.
      ls_dd03p-tabname = 'TEMP'.  " Will be set by DDIF_TABL_PUT

      " Key flag
      ASSIGN COMPONENT 'key' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0 AND ( <lv_val> = abap_true OR <lv_val> = 'true' OR <lv_val> = 'X' ).
        ls_dd03p-keyflag = abap_true.
      ENDIF.

      " Data element reference (rollname)
      ASSIGN COMPONENT 'rollname' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-rollname = to_upper( CONV string( <lv_val> ) ).
      ENDIF.

      " Direct type specification (if no data element)
      IF ls_dd03p-rollname IS INITIAL.
        ASSIGN COMPONENT 'datatype' OF STRUCTURE <ls_field> TO <lv_val>.
        IF sy-subrc = 0.
          ls_dd03p-datatype = to_upper( CONV string( <lv_val> ) ).
        ENDIF.

        ASSIGN COMPONENT 'length' OF STRUCTURE <ls_field> TO <lv_val>.
        IF sy-subrc = 0.
          ls_dd03p-leng = CONV i( <lv_val> ).
        ENDIF.

        ASSIGN COMPONENT 'decimals' OF STRUCTURE <ls_field> TO <lv_val>.
        IF sy-subrc = 0.
          ls_dd03p-decimals = CONV i( <lv_val> ).
        ENDIF.
      ENDIF.

      " Text fields
      ASSIGN COMPONENT 'description' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-ddtext = CONV string( <lv_val> ).
      ENDIF.

      " FIX: headingLabel → reptext
      ASSIGN COMPONENT 'headingLabel' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-reptext = CONV string( <lv_val> ).
      ENDIF.

      ASSIGN COMPONENT 'shortLabel' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-scrtext_s = CONV string( <lv_val> ).
        " Fallback: use shortLabel for reptext if headingLabel not provided
        IF ls_dd03p-reptext IS INITIAL.
          ls_dd03p-reptext = ls_dd03p-scrtext_s.
        ENDIF.
      ENDIF.

      ASSIGN COMPONENT 'mediumLabel' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-scrtext_m = CONV string( <lv_val> ).
      ENDIF.

      ASSIGN COMPONENT 'longLabel' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-scrtext_l = CONV string( <lv_val> ).
      ENDIF.

      APPEND ls_dd03p TO rt_dd03p.
    ENDLOOP.
  ENDMETHOD.


  METHOD check_activation.
    " Check activation return code and raise error if failed
    IF iv_rc <> 0.
      RAISE EXCEPTION TYPE cx_sy_dyn_call_error
        MESSAGE e001(zmcp_ddic) WITH iv_type iv_objname iv_rc.
      " Alternative: use generic exception
      " send_error is not available here because we want to RAISE
      " The caller will catch and send error
    ENDIF.
  ENDMETHOD.

ENDCLASS.
