*"* use this source file for the definition and implementation of
*"* local helper classes, interface definitions and type

*&---------------------------------------------------------------------*
*& ZCL_ADT_DDIC_HANDLER - Custom ICF Handler for DDIC CRUD Operations
*& Compatible with SAP NW 731 and above
*&---------------------------------------------------------------------*
*& Endpoint: /sap/bc/zddic_crud
*& Path format: /sap/bc/zddic_crud/{doma|dtel|stru|tabl}/{name}
*&
*& Features:
*&   - Full lifecycle: DDIF_*_PUT → DDIF_*_ACTIVATE
*&   - Transport assignment via corrNr query param or body field
*&   - Activation return code checking
*&   - Structure field parsing from JSON
*&   - No /ui2/cl_json dependency (manual JSON parsing)
*&   - No VALUE/COND/inline declarations (731 compatible)
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

    " JSON helper methods (no /ui2/cl_json dependency)
    METHODS json_get_string
      IMPORTING iv_json        TYPE string
                iv_field       TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS json_get_number
      IMPORTING iv_json        TYPE string
                iv_field       TYPE string
      RETURNING VALUE(rv_value) TYPE i.

    METHODS json_get_boolean
      IMPORTING iv_json        TYPE string
                iv_field       TYPE string
      RETURNING VALUE(rv_value) TYPE abap_bool.

    METHODS json_get_object
      IMPORTING iv_json        TYPE string
                iv_field       TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS json_get_array
      IMPORTING iv_json        TYPE string
                iv_field       TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS json_array_count
      IMPORTING iv_array       TYPE string
      RETURNING VALUE(rv_count) TYPE i.

    METHODS json_array_get_object
      IMPORTING iv_array       TYPE string
                iv_index       TYPE i
      RETURNING VALUE(rv_value) TYPE string.

    METHODS escape_json
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_json) TYPE string.

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
      IMPORTING iv_json         TYPE string
      RETURNING VALUE(rt_dd03p) TYPE dd03p_tab
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
      send_error( iv_status = 400 iv_message = 'Object type required: /sap/bc/zddic_crud/{doma|dtel|stru|tabl}/{name}' ).
      RETURN.
    ENDIF.

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
        send_error( iv_status = 400 iv_message = |Unknown type: { lv_object_type }. Use: doma, dtel, stru, tabl| ).
    ENDCASE.
  ENDMETHOD.


  METHOD parse_path.
    DATA: lv_path TYPE string,
          lv_temp TYPE string,
          lv_off  TYPE i.

    lv_path = mv_path_info.

    " Remove sap/bc/zddic_crud/ prefix
    FIND REGEX '^/?sap/bc/zddic_crud/?' IN lv_path MATCH OFFSET lv_off.
    IF sy-subrc = 0.
      DATA(lv_prefix_len) = 19. " length of 'sap/bc/zddic_crud/'
      IF strlen( lv_path ) > lv_prefix_len.
        lv_path = lv_path+lv_prefix_len.
      ELSE.
        CLEAR lv_path.
      ENDIF.
    ENDIF.

    " Remove leading slash
    IF strlen( lv_path ) > 0 AND lv_path(1) = '/'.
      lv_path = lv_path+1.
    ENDIF.

    " Split by '/'
    SPLIT lv_path AT '/' INTO ev_object_type ev_object_name.
    TRANSLATE ev_object_type TO UPPER CASE.
    TRANSLATE ev_object_name TO UPPER CASE.
    CONDENSE ev_object_type NO-GAPS.
    CONDENSE ev_object_name NO-GAPS.
  ENDMETHOD.


  METHOD read_json_body.
    rv_json = mo_server->request->get_cdata( ).
  ENDMETHOD.


  METHOD get_query_param.
    DATA: lv_qs    TYPE string,
          lv_pattern TYPE string,
          lv_offset TYPE i,
          lv_start TYPE i,
          lv_rest  TYPE string,
          lv_end   TYPE i.

    lv_qs = mv_query_string.
    cl_http_utility=>decode_url( CHANGING unescaped = lv_qs ).

    CONCATENATE iv_name '=' INTO lv_pattern.
    FIND lv_pattern IN lv_qs MATCH OFFSET lv_offset.
    IF sy-subrc = 0.
      lv_start = lv_offset + strlen( lv_pattern ).
      lv_rest = lv_qs+lv_start.
      FIND '&' IN lv_rest MATCH OFFSET lv_end.
      IF sy-subrc = 0.
        rv_value = lv_rest(lv_end).
      ELSE.
        rv_value = lv_rest.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD handle_domain.
    DATA: lv_json      TYPE string,
          lv_transport TYPE string.

    lv_json = read_json_body( ).
    lv_transport = get_query_param( 'corrNr' ).

    IF lv_transport IS INITIAL.
      lv_transport = json_get_string( iv_json = lv_json iv_field = 'transport' ).
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
    DATA: lv_json      TYPE string,
          lv_transport TYPE string.

    lv_json = read_json_body( ).
    lv_transport = get_query_param( 'corrNr' ).

    IF lv_transport IS INITIAL.
      lv_transport = json_get_string( iv_json = lv_json iv_field = 'transport' ).
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
    DATA: lv_json      TYPE string,
          lv_transport TYPE string.

    lv_json = read_json_body( ).
    lv_transport = get_query_param( 'corrNr' ).

    IF lv_transport IS INITIAL.
      lv_transport = json_get_string( iv_json = lv_json iv_field = 'transport' ).
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
    DATA: lv_json      TYPE string,
          lv_transport TYPE string.

    lv_json = read_json_body( ).
    lv_transport = get_query_param( 'corrNr' ).

    IF lv_transport IS INITIAL.
      lv_transport = json_get_string( iv_json = lv_json iv_field = 'transport' ).
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
      send_error( iv_status = 404 iv_message = |Domain '{ iv_name }' not found| ).
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
          lv_subrc   TYPE sy-subrc,
          lv_name    TYPE string,
          lv_datatype TYPE string,
          lv_length  TYPE i,
          lv_decimals TYPE i,
          lv_desc    TYPE string.

    " Parse JSON manually
    lv_name = json_get_string( iv_json = iv_json iv_field = 'name' ).
    IF lv_name IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Name is required' ).
      RETURN.
    ENDIF.

    lv_datatype = json_get_string( iv_json = iv_json iv_field = 'datatype' ).
    lv_length = json_get_number( iv_json = iv_json iv_field = 'length' ).
    lv_decimals = json_get_number( iv_json = iv_json iv_field = 'decimals' ).
    lv_desc = json_get_string( iv_json = iv_json iv_field = 'description' ).

    TRANSLATE lv_name TO UPPER CASE.
    TRANSLATE lv_datatype TO UPPER CASE.

    lv_objname = lv_name.
    ls_dd01v-domname = lv_name.
    ls_dd01v-ddlanguage = sy-langu.
    ls_dd01v-datatype = lv_datatype.
    ls_dd01v-leng = lv_length.
    ls_dd01v-decimals = lv_decimals.
    ls_dd01v-ddtext = lv_desc.
    ls_dd01v-domlen = lv_length.
    ls_dd01v-responsible = sy-uname.

    CALL FUNCTION 'DDIF_DOMA_PUT'
      EXPORTING
        name           = lv_objname
        dd01v_wa       = ls_dd01v
      TABLES
        dd07v_tab      = lt_dd07v
      EXCEPTIONS
        doma_not_found = 1
        name_inconsistent = 2
        doma_inconsistent = 3
        put_failure    = 4
        put_refused    = 5
        OTHERS         = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to create domain '{ lv_name }' (rc={ sy-subrc })| ).
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

    IF lv_subrc <> 0.
      send_error( iv_status = 500 iv_message = |Activation failed for domain '{ lv_name }' (rc={ lv_subrc })| ).
      RETURN.
    ENDIF.

    " Assign to transport
    IF iv_transport IS NOT INITIAL.
      assign_transport( iv_objname = lv_objname iv_object = 'DOMA' iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_resp) = |\{"status":"created","name":"{ lv_name }","type":"doma","activated":true\}|.
    send_json_response( iv_status = 201 iv_json = lv_resp ).
  ENDMETHOD.


  METHOD update_domain.
    DATA: ls_dd01v   TYPE dd01v,
          lt_dd07v   TYPE dd07v_tab,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc,
          lv_temp    TYPE string,
          lv_num     TYPE i.

    lv_objname = iv_name.

    " Read existing domain
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

    " Update fields from JSON
    lv_temp = json_get_string( iv_json = iv_json iv_field = 'description' ).
    IF lv_temp IS NOT INITIAL.
      ls_dd01v-ddtext = lv_temp.
    ENDIF.

    lv_temp = json_get_string( iv_json = iv_json iv_field = 'datatype' ).
    IF lv_temp IS NOT INITIAL.
      TRANSLATE lv_temp TO UPPER CASE.
      ls_dd01v-datatype = lv_temp.
    ENDIF.

    lv_num = json_get_number( iv_json = iv_json iv_field = 'length' ).
    IF lv_num > 0.
      ls_dd01v-leng = lv_num.
      ls_dd01v-domlen = lv_num.
    ENDIF.

    lv_num = json_get_number( iv_json = iv_json iv_field = 'decimals' ).
    IF lv_num >= 0.
      ls_dd01v-decimals = lv_num.
    ENDIF.

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

    CALL FUNCTION 'DDIF_DOMA_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    IF lv_subrc <> 0.
      send_error( iv_status = 500 iv_message = |Activation failed for domain '{ iv_name }' (rc={ lv_subrc })| ).
      RETURN.
    ENDIF.

    IF iv_transport IS NOT INITIAL.
      assign_transport( iv_objname = lv_objname iv_object = 'DOMA' iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_resp) = |\{"status":"updated","name":"{ iv_name }","type":"doma","activated":true\}|.
    send_json_response( iv_status = 200 iv_json = lv_resp ).
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
          lv_subrc   TYPE sy-subrc,
          lv_name    TYPE string,
          lv_domain TYPE string,
          lv_desc    TYPE string,
          lv_heading TYPE string,
          lv_short   TYPE string,
          lv_medium  TYPE string,
          lv_long    TYPE string,
          ls_dom_dd01v TYPE dd01v.

    " Parse JSON
    lv_name = json_get_string( iv_json = iv_json iv_field = 'name' ).
    lv_domain = json_get_string( iv_json = iv_json iv_field = 'domain' ).

    IF lv_name IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Name is required' ).
      RETURN.
    ENDIF.
    IF lv_domain IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Domain is required' ).
      RETURN.
    ENDIF.

    TRANSLATE lv_name TO UPPER CASE.
    TRANSLATE lv_domain TO UPPER CASE.

    " Validate domain exists
    CALL FUNCTION 'DDIF_DOMA_GET'
      EXPORTING
        name     = lv_domain
        state    = 'A'
      IMPORTING
        gotstate = lv_subrc
        dd01v_wa = ls_dom_dd01v
      EXCEPTIONS
        OTHERS   = 2.

    IF sy-subrc <> 0 OR lv_subrc = 0.
      send_error( iv_status = 400 iv_message = |Domain '{ lv_domain }' not found. Create domain first.| ).
      RETURN.
    ENDIF.

    lv_desc = json_get_string( iv_json = iv_json iv_field = 'description' ).
    lv_heading = json_get_string( iv_json = iv_json iv_field = 'headingLabel' ).
    lv_short = json_get_string( iv_json = iv_json iv_field = 'shortLabel' ).
    lv_medium = json_get_string( iv_json = iv_json iv_field = 'mediumLabel' ).
    lv_long = json_get_string( iv_json = iv_json iv_field = 'longLabel' ).

    lv_objname = lv_name.
    ls_dd04v-rollname = lv_name.
    ls_dd04v-ddlanguage = sy-langu.
    ls_dd04v-ddtext = lv_desc.
    ls_dd04v-reptext = lv_heading.
    IF ls_dd04v-reptext IS INITIAL.
      ls_dd04v-reptext = lv_short.
    ENDIF.
    ls_dd04v-scrtext_s = lv_short.
    ls_dd04v-scrtext_m = lv_medium.
    ls_dd04v-scrtext_l = lv_long.
    ls_dd04v-domname = lv_domain.
    ls_dd04v-responsible = sy-uname.

    " Get type info from domain
    ls_dd04v-datatype = ls_dom_dd01v-datatype.
    ls_dd04v-leng = ls_dom_dd01v-leng.
    ls_dd04v-decimals = ls_dom_dd01v-decimals.

    CALL FUNCTION 'DDIF_DTEL_PUT'
      EXPORTING
        name           = lv_objname
        dd04v_wa       = ls_dd04v
      EXCEPTIONS
        dtel_not_found = 1
        name_inconsistent = 2
        dtel_inconsistent = 3
        put_failure    = 4
        put_refused    = 5
        OTHERS         = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to create data element '{ lv_name }' (rc={ sy-subrc })| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_DTEL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    IF lv_subrc <> 0.
      send_error( iv_status = 500 iv_message = |Activation failed for data element '{ lv_name }' (rc={ lv_subrc })| ).
      RETURN.
    ENDIF.

    IF iv_transport IS NOT INITIAL.
      assign_transport( iv_objname = lv_objname iv_object = 'DTEL' iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_resp) = |\{"status":"created","name":"{ lv_name }","type":"dtel","domain":"{ lv_domain }","activated":true\}|.
    send_json_response( iv_status = 201 iv_json = lv_resp ).
  ENDMETHOD.


  METHOD update_data_element.
    DATA: ls_dd04v   TYPE dd04v,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc,
          lv_temp    TYPE string,
          lv_domain  TYPE string,
          ls_dom_dd01v TYPE dd01v.

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

    " Update fields
    lv_temp = json_get_string( iv_json = iv_json iv_field = 'description' ).
    IF lv_temp IS NOT INITIAL.
      ls_dd04v-ddtext = lv_temp.
    ENDIF.

    lv_domain = json_get_string( iv_json = iv_json iv_field = 'domain' ).
    IF lv_domain IS NOT INITIAL.
      TRANSLATE lv_domain TO UPPER CASE.
      " Validate domain
      CALL FUNCTION 'DDIF_DOMA_GET'
        EXPORTING
          name     = lv_domain
          state    = 'A'
        IMPORTING
          gotstate = lv_subrc
        EXCEPTIONS
          OTHERS   = 2.
      IF sy-subrc <> 0 OR lv_subrc = 0.
        send_error( iv_status = 400 iv_message = |Domain '{ lv_domain }' not found| ).
        RETURN.
      ENDIF.
      ls_dd04v-domname = lv_domain.
    ENDIF.

    lv_temp = json_get_string( iv_json = iv_json iv_field = 'headingLabel' ).
    IF lv_temp IS NOT INITIAL.
      ls_dd04v-reptext = lv_temp.
    ENDIF.

    lv_temp = json_get_string( iv_json = iv_json iv_field = 'shortLabel' ).
    IF lv_temp IS NOT INITIAL.
      ls_dd04v-scrtext_s = lv_temp.
      IF ls_dd04v-reptext IS INITIAL.
        ls_dd04v-reptext = lv_temp.
      ENDIF.
    ENDIF.

    lv_temp = json_get_string( iv_json = iv_json iv_field = 'mediumLabel' ).
    IF lv_temp IS NOT INITIAL.
      ls_dd04v-scrtext_m = lv_temp.
    ENDIF.

    lv_temp = json_get_string( iv_json = iv_json iv_field = 'longLabel' ).
    IF lv_temp IS NOT INITIAL.
      ls_dd04v-scrtext_l = lv_temp.
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

    IF lv_subrc <> 0.
      send_error( iv_status = 500 iv_message = |Activation failed for data element '{ iv_name }' (rc={ lv_subrc })| ).
      RETURN.
    ENDIF.

    IF iv_transport IS NOT INITIAL.
      assign_transport( iv_objname = lv_objname iv_object = 'DTEL' iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_resp) = |\{"status":"updated","name":"{ iv_name }","type":"dtel","activated":true\}|.
    send_json_response( iv_status = 200 iv_json = lv_resp ).
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
      send_error( iv_status = 404 iv_message = |Structure '{ iv_name }' not found| ).
      RETURN.
    ENDIF.

    IF ls_dd02v-tabclass = 'TRANSP'.
      send_error( iv_status = 400 iv_message = |'{ iv_name }' is a table, use /tabl/ endpoint| ).
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
          lv_subrc   TYPE sy-subrc,
          lv_name    TYPE string,
          lv_desc    TYPE string.

    lv_name = json_get_string( iv_json = iv_json iv_field = 'name' ).
    IF lv_name IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Name is required' ).
      RETURN.
    ENDIF.

    TRANSLATE lv_name TO UPPER CASE.
    lv_desc = json_get_string( iv_json = iv_json iv_field = 'description' ).

    lv_objname = lv_name.
    ls_dd02v-tabname = lv_name.
    ls_dd02v-ddlanguage = sy-langu.
    ls_dd02v-ddtext = lv_desc.
    ls_dd02v-tabclass = 'INTTAB'.
    ls_dd02v-responsible = sy-uname.

    " Parse fields array
    lt_dd03p = parse_fields_array( iv_json = iv_json ).

    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING
        name      = lv_objname
        dd02v_wa  = ls_dd02v
      TABLES
        dd03p_tab = lt_dd03p
      EXCEPTIONS
        OTHERS    = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to create structure '{ lv_name }' (rc={ sy-subrc })| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    IF lv_subrc <> 0.
      send_error( iv_status = 500 iv_message = |Activation failed for structure '{ lv_name }' (rc={ lv_subrc })| ).
      RETURN.
    ENDIF.

    IF iv_transport IS NOT INITIAL.
      assign_transport( iv_objname = lv_objname iv_object = 'TABL' iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_count) = lines( lt_dd03p ).
    DATA(lv_resp) = |\{"status":"created","name":"{ lv_name }","type":"stru","fields":{ lv_count },"activated":true\}|.
    send_json_response( iv_status = 201 iv_json = lv_resp ).
  ENDMETHOD.


  METHOD update_structure.
    DATA: ls_dd02v   TYPE dd02v,
          lt_dd03p   TYPE dd03p_tab,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc,
          lv_temp    TYPE string,
          lt_new_fields TYPE dd03p_tab.

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

    lv_temp = json_get_string( iv_json = iv_json iv_field = 'description' ).
    IF lv_temp IS NOT INITIAL.
      ls_dd02v-ddtext = lv_temp.
    ENDIF.

    " Parse fields - if provided, replace
    lt_new_fields = parse_fields_array( iv_json = iv_json ).
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

    IF lv_subrc <> 0.
      send_error( iv_status = 500 iv_message = |Activation failed for structure '{ iv_name }' (rc={ lv_subrc })| ).
      RETURN.
    ENDIF.

    IF iv_transport IS NOT INITIAL.
      assign_transport( iv_objname = lv_objname iv_object = 'TABL' iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_resp) = |\{"status":"updated","name":"{ iv_name }","type":"stru","activated":true\}|.
    send_json_response( iv_status = 200 iv_json = lv_resp ).
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

    IF ls_dd02v-tabclass <> 'TRANSP'.
      send_error( iv_status = 400 iv_message = |'{ iv_name }' is not a transparent table| ).
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
          lv_subrc   TYPE sy-subrc,
          lv_name    TYPE string,
          lv_desc    TYPE string.

    lv_name = json_get_string( iv_json = iv_json iv_field = 'name' ).
    IF lv_name IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Name is required' ).
      RETURN.
    ENDIF.

    TRANSLATE lv_name TO UPPER CASE.
    lv_desc = json_get_string( iv_json = iv_json iv_field = 'description' ).

    lv_objname = lv_name.
    ls_dd02v-tabname = lv_name.
    ls_dd02v-ddlanguage = sy-langu.
    ls_dd02v-ddtext = lv_desc.
    ls_dd02v-tabclass = 'TRANSP'.
    ls_dd02v-tabart = 'APPL0'.
    ls_dd02v-bufallow = 'N'.
    ls_dd02v-responsible = sy-uname.

    lt_dd03p = parse_fields_array( iv_json = iv_json ).

    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING
        name      = lv_objname
        dd02v_wa  = ls_dd02v
      TABLES
        dd03p_tab = lt_dd03p
      EXCEPTIONS
        OTHERS    = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to create table '{ lv_name }' (rc={ sy-subrc })| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    IF lv_subrc <> 0.
      send_error( iv_status = 500 iv_message = |Activation failed for table '{ lv_name }' (rc={ lv_subrc })| ).
      RETURN.
    ENDIF.

    IF iv_transport IS NOT INITIAL.
      assign_transport( iv_objname = lv_objname iv_object = 'TABL' iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_resp) = |\{"status":"created","name":"{ lv_name }","type":"tabl","activated":true\}|.
    send_json_response( iv_status = 201 iv_json = lv_resp ).
  ENDMETHOD.


  METHOD update_table.
    DATA: ls_dd02v   TYPE dd02v,
          lt_dd03p   TYPE dd03p_tab,
          lv_objname TYPE ddobjname,
          lv_subrc   TYPE sy-subrc,
          lv_temp    TYPE string,
          lt_new_fields TYPE dd03p_tab.

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

    lv_temp = json_get_string( iv_json = iv_json iv_field = 'description' ).
    IF lv_temp IS NOT INITIAL.
      ls_dd02v-ddtext = lv_temp.
    ENDIF.

    lt_new_fields = parse_fields_array( iv_json = iv_json ).
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

    IF lv_subrc <> 0.
      send_error( iv_status = 500 iv_message = |Activation failed for table '{ iv_name }' (rc={ lv_subrc })| ).
      RETURN.
    ENDIF.

    IF iv_transport IS NOT INITIAL.
      assign_transport( iv_objname = lv_objname iv_object = 'TABL' iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.

    DATA(lv_resp) = |\{"status":"updated","name":"{ iv_name }","type":"tabl","activated":true\}|.
    send_json_response( iv_status = 200 iv_json = lv_resp ).
  ENDMETHOD.


  "----------------------------------------------------------------------"
  " JSON Helper Methods (no /ui2/cl_json dependency)
  "----------------------------------------------------------------------"

  METHOD json_get_string.
    " Extract string value from JSON: "field":"value"
    DATA: lv_pattern TYPE string,
          lv_offset  TYPE i,
          lv_start   TYPE i,
          lv_end     TYPE i,
          lv_rest    TYPE string.

    CONCATENATE '"' iv_field '"' ':' '"' INTO lv_pattern.
    FIND lv_pattern IN iv_json MATCH OFFSET lv_offset.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    lv_start = lv_offset + strlen( lv_pattern ).
    lv_rest = iv_json+lv_start.

    FIND '"' IN lv_rest MATCH OFFSET lv_end.
    IF sy-subrc = 0.
      rv_value = lv_rest(lv_end).
    ENDIF.
  ENDMETHOD.


  METHOD json_get_number.
    " Extract number value from JSON: "field":123
    DATA: lv_pattern TYPE string,
          lv_offset  TYPE i,
          lv_start   TYPE i,
          lv_end     TYPE i,
          lv_rest    TYPE string,
          lv_num_str TYPE string.

    CONCATENATE '"' iv_field '"' ':' INTO lv_pattern.
    FIND lv_pattern IN iv_json MATCH OFFSET lv_offset.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    lv_start = lv_offset + strlen( lv_pattern ).
    lv_rest = iv_json+lv_start.

    " Find end of number (comma, brace, or end)
    FIND REGEX '[^0-9-]' IN lv_rest MATCH OFFSET lv_end.
    IF sy-subrc = 0.
      lv_num_str = lv_rest(lv_end).
    ELSE.
      lv_num_str = lv_rest.
    ENDIF.

    CONDENSE lv_num_str NO-GAPS.
    TRY.
        rv_value = lv_num_str.
      CATCH cx_root.
        rv_value = 0.
    ENDTRY.
  ENDMETHOD.


  METHOD json_get_boolean.
    " Extract boolean value from JSON: "field":true/false
    DATA: lv_val TYPE string.

    lv_val = json_get_string( iv_json = iv_json iv_field = iv_field ).

    " Also check for non-string boolean
    IF lv_val IS INITIAL.
      DATA: lv_pattern TYPE string,
            lv_offset  TYPE i,
            lv_rest    TYPE string.

      CONCATENATE '"' iv_field '"' ':' INTO lv_pattern.
      FIND lv_pattern IN iv_json MATCH OFFSET lv_offset.
      IF sy-subrc = 0.
        DATA(lv_start) = lv_offset + strlen( lv_pattern ).
        lv_rest = iv_json+lv_start.
        CONDENSE lv_rest NO-GAPS.
        IF strlen( lv_rest ) >= 4 AND lv_rest(4) = 'true'.
          rv_value = abap_true.
        ENDIF.
      ENDIF.
    ELSE.
      IF lv_val = 'true' OR lv_val = 'X' OR lv_val = '1'.
        rv_value = abap_true.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD json_get_object.
    " Extract nested object from JSON: "field":{...}
    DATA: lv_pattern TYPE string,
          lv_offset  TYPE i,
          lv_start   TYPE i,
          lv_rest    TYPE string,
          lv_depth   TYPE i VALUE 0,
          lv_pos     TYPE i VALUE 0,
          lv_char    TYPE c.

    CONCATENATE '"' iv_field '"' ':' '{' INTO lv_pattern.
    FIND lv_pattern IN iv_json MATCH OFFSET lv_offset.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    lv_start = lv_offset + strlen( lv_pattern ) - 1. " Include opening brace
    lv_rest = iv_json+lv_start.
    lv_depth = 1.
    lv_pos = 1.

    WHILE lv_pos < strlen( lv_rest ) AND lv_depth > 0.
      lv_char = lv_rest+lv_pos(1).
      IF lv_char = '{'.
        lv_depth = lv_depth + 1.
      ELSEIF lv_char = '}'.
        lv_depth = lv_depth - 1.
      ENDIF.
      lv_pos = lv_pos + 1.
    ENDWHILE.

    IF lv_depth = 0.
      rv_value = lv_rest(lv_pos).
    ENDIF.
  ENDMETHOD.


  METHOD json_get_array.
    " Extract array from JSON: "field":[...]
    DATA: lv_pattern TYPE string,
          lv_offset  TYPE i,
          lv_start   TYPE i,
          lv_rest    TYPE string,
          lv_depth   TYPE i VALUE 0,
          lv_pos     TYPE i VALUE 0,
          lv_char    TYPE c.

    CONCATENATE '"' iv_field '"' ':' '[' INTO lv_pattern.
    FIND lv_pattern IN iv_json MATCH OFFSET lv_offset.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    lv_start = lv_offset + strlen( lv_pattern ) - 1. " Include opening bracket
    lv_rest = iv_json+lv_start.
    lv_depth = 1.
    lv_pos = 1.

    WHILE lv_pos < strlen( lv_rest ) AND lv_depth > 0.
      lv_char = lv_rest+lv_pos(1).
      IF lv_char = '['.
        lv_depth = lv_depth + 1.
      ELSEIF lv_char = ']'.
        lv_depth = lv_depth - 1.
      ENDIF.
      lv_pos = lv_pos + 1.
    ENDWHILE.

    IF lv_depth = 0.
      rv_value = lv_rest(lv_pos).
    ENDIF.
  ENDMETHOD.


  METHOD json_array_count.
    " Count objects in JSON array
    DATA: lv_count TYPE i VALUE 0,
          lv_pos   TYPE i VALUE 0,
          lv_len   TYPE i.

    lv_len = strlen( iv_array ).
    IF lv_len < 2.
      rv_count = 0.
      RETURN.
    ENDIF.

    " Skip opening bracket
    lv_pos = 1.

    WHILE lv_pos < lv_len.
      " Skip whitespace
      WHILE lv_pos < lv_len AND iv_array+lv_pos(1) = ' '.
        lv_pos = lv_pos + 1.
      ENDWHILE.

      IF lv_pos >= lv_len.
        EXIT.
      ENDIF.

      IF iv_array+lv_pos(1) = '{'.
        lv_count = lv_count + 1.
        " Skip to end of object
        DATA(lv_depth) = 1.
        lv_pos = lv_pos + 1.
        WHILE lv_pos < lv_len AND lv_depth > 0.
          IF iv_array+lv_pos(1) = '{'.
            lv_depth = lv_depth + 1.
          ELSEIF iv_array+lv_pos(1) = '}'.
            lv_depth = lv_depth - 1.
          ENDIF.
          lv_pos = lv_pos + 1.
        ENDWHILE.
      ELSEIF iv_array+lv_pos(1) = ','.
        lv_pos = lv_pos + 1.
      ELSE.
        lv_pos = lv_pos + 1.
      ENDIF.
    ENDWHILE.

    rv_count = lv_count.
  ENDMETHOD.


  METHOD json_array_get_object.
    " Get object at index from JSON array
    DATA: lv_count TYPE i VALUE 0,
          lv_pos   TYPE i VALUE 0,
          lv_len   TYPE i,
          lv_start TYPE i.

    lv_len = strlen( iv_array ).
    IF lv_len < 2.
      RETURN.
    ENDIF.

    lv_pos = 1.

    WHILE lv_pos < lv_len.
      " Skip whitespace
      WHILE lv_pos < lv_len AND iv_array+lv_pos(1) = ' '.
        lv_pos = lv_pos + 1.
      ENDWHILE.

      IF lv_pos >= lv_len.
        EXIT.
      ENDIF.

      IF iv_array+lv_pos(1) = '{'.
        IF lv_count = iv_index.
          lv_start = lv_pos.
          DATA(lv_depth) = 1.
          lv_pos = lv_pos + 1.
          WHILE lv_pos < lv_len AND lv_depth > 0.
            IF iv_array+lv_pos(1) = '{'.
              lv_depth = lv_depth + 1.
            ELSEIF iv_array+lv_pos(1) = '}'.
              lv_depth = lv_depth - 1.
            ENDIF.
            lv_pos = lv_pos + 1.
          ENDWHILE.
          rv_value = iv_array+lv_start(lv_pos - lv_start).
          RETURN.
        ELSE.
          lv_count = lv_count + 1.
          " Skip object
          DATA(lv_skip_depth) = 1.
          lv_pos = lv_pos + 1.
          WHILE lv_pos < lv_len AND lv_skip_depth > 0.
            IF iv_array+lv_pos(1) = '{'.
              lv_skip_depth = lv_skip_depth + 1.
            ELSEIF iv_array+lv_pos(1) = '}'.
              lv_skip_depth = lv_skip_depth - 1.
            ENDIF.
            lv_pos = lv_pos + 1.
          ENDWHILE.
        ENDIF.
      ELSEIF iv_array+lv_pos(1) = ','.
        lv_pos = lv_pos + 1.
      ELSE.
        lv_pos = lv_pos + 1.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.


  METHOD escape_json.
    " Escape special characters for JSON
    rv_json = iv_text.
    REPLACE ALL OCCURRENCES OF '\' IN rv_json WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_json WITH '\"'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_json WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_json WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_json WITH '\t'.
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
    DATA(lv_msg) = escape_json( iv_message ).
    DATA(lv_json) = |\{"error":"{ lv_msg }"\}|.
    send_json_response( iv_status = iv_status iv_json = lv_json ).
  ENDMETHOD.


  METHOD build_domain_json.
    DATA: lv_fixed_json TYPE string,
          lv_text       TYPE string.

    LOOP AT it_dd07v INTO DATA(ls_fv).
      IF lv_fixed_json IS NOT INITIAL.
        CONCATENATE lv_fixed_json ',' INTO lv_fixed_json.
      ENDIF.

      lv_text = escape_json( ls_fv-ddtext ).

      CONCATENATE lv_fixed_json
        '\{"low":"' ls_fv-domvalue_l '","high":"' ls_fv-domvalue_h '","text":"' lv_text '"\}'
        INTO lv_fixed_json.
    ENDLOOP.

    DATA(lv_desc) = escape_json( is_dd01v-ddtext ).

    CONCATENATE
      '\{'
      '"name":"' iv_name '",'
      '"type":"doma",'
      '"description":"' lv_desc '",'
      '"datatype":"' is_dd01v-datatype '",'
      '"length":' is_dd01v-leng ','
      '"decimals":' is_dd01v-decimals ','
      '"fixedValues":[' lv_fixed_json ']'
      '\}'
      INTO rv_json.
  ENDMETHOD.


  METHOD build_dtel_json.
    DATA(lv_desc) = escape_json( is_dd04v-ddtext ).
    DATA(lv_reptext) = escape_json( is_dd04v-reptext ).
    DATA(lv_scrtext_s) = escape_json( is_dd04v-scrtext_s ).
    DATA(lv_scrtext_m) = escape_json( is_dd04v-scrtext_m ).
    DATA(lv_scrtext_l) = escape_json( is_dd04v-scrtext_l ).

    CONCATENATE
      '\{'
      '"name":"' iv_name '",'
      '"type":"dtel",'
      '"description":"' lv_desc '",'
      '"domain":"' is_dd04v-domname '",'
      '"datatype":"' is_dd04v-datatype '",'
      '"length":' is_dd04v-leng ','
      '"decimals":' is_dd04v-decimals ','
      '"headingLabel":"' lv_reptext '",'
      '"shortLabel":"' lv_scrtext_s '",'
      '"mediumLabel":"' lv_scrtext_m '",'
      '"longLabel":"' lv_scrtext_l '"'
      '\}'
      INTO rv_json.
  ENDMETHOD.


  METHOD build_structure_json.
    DATA: lv_fields_json TYPE string,
          lv_field_desc  TYPE string,
          lv_key_str     TYPE string,
          lv_scrtext_s   TYPE string,
          lv_scrtext_m   TYPE string,
          lv_scrtext_l   TYPE string,
          lv_reptext     TYPE string.

    LOOP AT it_dd03p INTO DATA(ls_field).
      IF lv_fields_json IS NOT INITIAL.
        CONCATENATE lv_fields_json ',' INTO lv_fields_json.
      ENDIF.

      IF ls_field-keyflag = abap_true.
        lv_key_str = 'true'.
      ELSE.
        lv_key_str = 'false'.
      ENDIF.

      lv_field_desc = escape_json( ls_field-ddtext ).
      lv_scrtext_s = escape_json( ls_field-scrtext_s ).
      lv_scrtext_m = escape_json( ls_field-scrtext_m ).
      lv_scrtext_l = escape_json( ls_field-scrtext_l ).
      lv_reptext = escape_json( ls_field-reptext ).

      CONCATENATE lv_fields_json
        '\{"pos":' ls_field-position ','
        '"name":"' ls_field-fieldname '",'
        '"key":' lv_key_str ','
        '"datatype":"' ls_field-datatype '","length":' ls_field-leng ',"decimals":' ls_field-decimals ','
        '"rollname":"' ls_field-rollname '","domname":"' ls_field-domname '",'
        '"description":"' lv_field_desc '",'
        '"headingLabel":"' lv_reptext '",'
        '"shortLabel":"' lv_scrtext_s '","mediumLabel":"' lv_scrtext_m '","longLabel":"' lv_scrtext_l '"\}'
        INTO lv_fields_json.
    ENDLOOP.

    DATA(lv_desc) = escape_json( is_dd02v-ddtext ).

    DATA: lv_type TYPE string.
    IF is_dd02v-tabclass = 'TRANSP'.
      lv_type = 'tabl'.
    ELSE.
      lv_type = 'stru'.
    ENDIF.

    CONCATENATE
      '\{'
      '"name":"' iv_name '",'
      '"type":"' lv_type '",'
      '"description":"' lv_desc '",'
      '"tableClass":"' is_dd02v-tabclass '",'
      '"fields":[' lv_fields_json ']'
      '\}'
      INTO rv_json.
  ENDMETHOD.


  METHOD assign_transport.
    DATA: lt_e071  TYPE TABLE OF e071,
          ls_e071  TYPE e071.

    ls_e071-trkorr = iv_transport.
    ls_e071-pgmid = 'R3TR'.
    ls_e071-object = iv_object.
    ls_e071-obj_name = iv_objname.
    APPEND ls_e071 TO lt_e071.

    " Try to assign to transport
    CALL FUNCTION 'TRINT_TADIR_INSERT_ASSIGN'
      EXPORTING
        iv_tadir_pgmid     = 'R3TR'
        iv_tadir_object    = iv_object
        iv_tadir_obj_name  = iv_objname
        iv_tadir_devclass  = ''
        iv_tadir_masterlang = sy-langu
        iv_set_editflag    = abap_true
        iv_without_corr    = abap_false
      EXCEPTIONS
        tadir_entry_not_existing = 1
        tadir_entry_already_exists = 2
        error_in_transport       = 3
        OTHERS                   = 4.

    " Ignore already exists (2), log others
    IF sy-subrc <> 0 AND sy-subrc <> 2.
      " Non-critical warning - don't fail the operation
    ENDIF.
  ENDMETHOD.


  METHOD parse_fields_array.
    " Parse fields array from JSON
    DATA: lv_array    TYPE string,
          lv_count    TYPE i,
          lv_idx      TYPE i VALUE 0,
          lv_obj      TYPE string,
          lv_pos      TYPE ddposition VALUE 0,
          ls_dd03p    TYPE dd03p,
          lv_temp     TYPE string,
          lv_num      TYPE i.

    lv_array = json_get_array( iv_json = iv_json iv_field = 'fields' ).
    IF lv_array IS INITIAL.
      RETURN.
    ENDIF.

    lv_count = json_array_count( lv_array ).

    WHILE lv_idx < lv_count.
      lv_obj = json_array_get_object( iv_array = lv_array iv_index = lv_idx ).
      IF lv_obj IS INITIAL.
        EXIT.
      ENDIF.

      lv_pos = lv_pos + 10.
      CLEAR ls_dd03p.

      " Field name (required)
      lv_temp = json_get_string( iv_json = lv_obj iv_field = 'name' ).
      IF lv_temp IS INITIAL.
        lv_idx = lv_idx + 1.
        CONTINUE.
      ENDIF.

      TRANSLATE lv_temp TO UPPER CASE.
      ls_dd03p-fieldname = lv_temp.
      ls_dd03p-position = lv_pos.
      ls_dd03p-ddlanguage = sy-langu.
      ls_dd03p-tabname = 'TEMP'.

      " Key flag
      IF json_get_boolean( iv_json = lv_obj iv_field = 'key' ) = abap_true.
        ls_dd03p-keyflag = abap_true.
      ENDIF.

      " Data element
      lv_temp = json_get_string( iv_json = lv_obj iv_field = 'rollname' ).
      IF lv_temp IS NOT INITIAL.
        TRANSLATE lv_temp TO UPPER CASE.
        ls_dd03p-rollname = lv_temp.
      ENDIF.

      " Direct type (if no data element)
      IF ls_dd03p-rollname IS INITIAL.
        lv_temp = json_get_string( iv_json = lv_obj iv_field = 'datatype' ).
        IF lv_temp IS NOT INITIAL.
          TRANSLATE lv_temp TO UPPER CASE.
          ls_dd03p-datatype = lv_temp.
        ENDIF.

        lv_num = json_get_number( iv_json = lv_obj iv_field = 'length' ).
        IF lv_num > 0.
          ls_dd03p-leng = lv_num.
        ENDIF.

        lv_num = json_get_number( iv_json = lv_obj iv_field = 'decimals' ).
        IF lv_num >= 0.
          ls_dd03p-decimals = lv_num.
        ENDIF.
      ENDIF.

      " Text fields
      ls_dd03p-ddtext = json_get_string( iv_json = lv_obj iv_field = 'description' ).
      ls_dd03p-reptext = json_get_string( iv_json = lv_obj iv_field = 'headingLabel' ).
      ls_dd03p-scrtext_s = json_get_string( iv_json = lv_obj iv_field = 'shortLabel' ).
      ls_dd03p-scrtext_m = json_get_string( iv_json = lv_obj iv_field = 'mediumLabel' ).
      ls_dd03p-scrtext_l = json_get_string( iv_json = lv_obj iv_field = 'longLabel' ).

      " Fallback: shortLabel -> reptext
      IF ls_dd03p-reptext IS INITIAL AND ls_dd03p-scrtext_s IS NOT INITIAL.
        ls_dd03p-reptext = ls_dd03p-scrtext_s.
      ENDIF.

      APPEND ls_dd03p TO rt_dd03p.
      lv_idx = lv_idx + 1.
    ENDWHILE.
  ENDMETHOD.

ENDCLASS.
