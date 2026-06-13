*"* use this source file for the definition and implementation of
*"* local helper classes, interface definitions and type
*"* temporary helper classes, interface definitions and type
*"* temporary helper classes, interface definitions and type
*"* temporary helper classes, interface definitions and type
*"* temporary helper classes, interface definitions and type

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
          mo_server         TYPE REF TO if_http_server.

    METHODS parse_path
      EXPORTING
        ev_object_type TYPE string
        ev_object_name TYPE string.

    METHODS read_json_body
      RETURNING
        rv_json TYPE string.

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
      IMPORTING iv_json TYPE string
      RAISING  cx_root.

    METHODS update_domain
      IMPORTING iv_name TYPE string
                iv_json TYPE string
      RAISING  cx_root.

    METHODS read_data_element
      IMPORTING iv_name TYPE string
      RAISING  cx_root.

    METHODS create_data_element
      IMPORTING iv_json TYPE string
      RAISING  cx_root.

    METHODS update_data_element
      IMPORTING iv_name TYPE string
                iv_json TYPE string
      RAISING  cx_root.

    METHODS read_structure
      IMPORTING iv_name TYPE string
      RAISING  cx_root.

    METHODS create_structure
      IMPORTING iv_json TYPE string
      RAISING  cx_root.

    METHODS update_structure
      IMPORTING iv_name TYPE string
                iv_json TYPE string
      RAISING  cx_root.

    METHODS read_table
      IMPORTING iv_name TYPE string
      RAISING  cx_root.

    METHODS create_table
      IMPORTING iv_json TYPE string
      RAISING  cx_root.

    METHODS update_table
      IMPORTING iv_name TYPE string
                iv_json TYPE string
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

ENDCLASS.


CLASS zcl_adt_ddic_handler IMPLEMENTATION.

  METHOD if_http_extension~handle_request.
    mo_server = server.
    mv_request_method = server->request->get_header_field( name = '~request_method' ).
    mv_path_info = server->request->get_header_field( name = '~path_info' ).

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


  METHOD handle_domain.
    DATA(lv_json) = read_json_body( ).
    CASE iv_method.
      WHEN 'GET'.
        read_domain( iv_name = iv_name ).
      WHEN 'POST'.
        create_domain( iv_json = lv_json ).
      WHEN 'PUT'.
        update_domain( iv_name = iv_name iv_json = lv_json ).
      WHEN 'DELETE'.
        " TODO: implement delete
        send_error( iv_status = 501 iv_message = 'Delete not yet implemented' ).
      WHEN OTHERS.
        send_error( iv_status = 405 iv_message = |Method { iv_method } not allowed| ).
    ENDCASE.
  ENDMETHOD.


  METHOD handle_data_element.
    DATA(lv_json) = read_json_body( ).
    CASE iv_method.
      WHEN 'GET'.
        read_data_element( iv_name = iv_name ).
      WHEN 'POST'.
        create_data_element( iv_json = lv_json ).
      WHEN 'PUT'.
        update_data_element( iv_name = iv_name iv_json = lv_json ).
      WHEN 'DELETE'.
        send_error( iv_status = 501 iv_message = 'Delete not yet implemented' ).
      WHEN OTHERS.
        send_error( iv_status = 405 iv_message = |Method { iv_method } not allowed| ).
    ENDCASE.
  ENDMETHOD.


  METHOD handle_structure.
    DATA(lv_json) = read_json_body( ).
    CASE iv_method.
      WHEN 'GET'.
        read_structure( iv_name = iv_name ).
      WHEN 'POST'.
        create_structure( iv_json = lv_json ).
      WHEN 'PUT'.
        update_structure( iv_name = iv_name iv_json = lv_json ).
      WHEN 'DELETE'.
        send_error( iv_status = 501 iv_message = 'Delete not yet implemented' ).
      WHEN OTHERS.
        send_error( iv_status = 405 iv_message = |Method { iv_method } not allowed| ).
    ENDCASE.
  ENDMETHOD.


  METHOD handle_table.
    DATA(lv_json) = read_json_body( ).
    CASE iv_method.
      WHEN 'GET'.
        read_table( iv_name = iv_name ).
      WHEN 'POST'.
        create_table( iv_json = lv_json ).
      WHEN 'PUT'.
        update_table( iv_name = iv_name iv_json = lv_json ).
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
      send_error( iv_status = 404 iv_message = |Domain { iv_name } not found| ).
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

    " Get responsible user
    ls_dd01v-responsible = sy-uname.

    " Fixed values from JSON array
    " TODO: parse fixedValues array from JSON body

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
      send_error( iv_status = 500 iv_message = |Failed to create domain { lv_name }: sy-subrc={ sy-subrc }| ).
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

    DATA(lv_json) = |'\{"status":"created","name":"{ lv_name }","type":"doma"\}'|.
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
      send_error( iv_status = 404 iv_message = |Domain { iv_name } not found| ).
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
      send_error( iv_status = 500 iv_message = |Failed to update domain { iv_name }| ).
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

    DATA(lv_json) = |'\{"status":"updated","name":"{ iv_name }","type":"doma"\}'|.
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
      send_error( iv_status = 404 iv_message = |Data element { iv_name } not found| ).
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

    lv_objname = lv_name.
    ls_dd04v-rollname = lv_name.
    ls_dd04v-ddlanguage = sy-langu.
    ls_dd04v-datatype = get_string( io_data = lo_data iv_field = 'datatype' ).
    ls_dd04v-leng = get_number( io_data = lo_data iv_field = 'length' ).
    ls_dd04v-decimals = get_number( io_data = lo_data iv_field = 'decimals' ).
    ls_dd04v-ddtext = get_string( io_data = lo_data iv_field = 'description' ).
    ls_dd04v-reptext = get_string( io_data = lo_data iv_field = 'shortLabel' ).
    ls_dd04v-scrtext_s = get_string( io_data = lo_data iv_field = 'shortLabel' ).
    ls_dd04v-scrtext_m = get_string( io_data = lo_data iv_field = 'mediumLabel' ).
    ls_dd04v-scrtext_l = get_string( io_data = lo_data iv_field = 'longLabel' ).
    ls_dd04v-domname = get_string( io_data = lo_data iv_field = 'domain' ).
    ls_dd04v-responsible = sy-uname.

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
      send_error( iv_status = 500 iv_message = |Failed to create data element { lv_name }: sy-subrc={ sy-subrc }| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_DTEL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    DATA(lv_json) = |'\{"status":"created","name":"{ lv_name }","type":"dtel"\}'|.
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
      send_error( iv_status = 404 iv_message = |Data element { iv_name } not found| ).
      RETURN.
    ENDIF.

    DATA(lo_data) = json_decode( iv_json ).
    DATA(lv_desc) = get_string( io_data = lo_data iv_field = 'description' ).
    IF lv_desc IS NOT INITIAL.
      ls_dd04v-ddtext = lv_desc.
    ENDIF.
    DATA(lv_domain) = get_string( io_data = lo_data iv_field = 'domain' ).
    IF lv_domain IS NOT INITIAL.
      ls_dd04v-domname = lv_domain.
    ENDIF.

    CALL FUNCTION 'DDIF_DTEL_PUT'
      EXPORTING
        name     = lv_objname
        dd04v_wa = ls_dd04v
      EXCEPTIONS
        OTHERS   = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to update data element { iv_name }| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_DTEL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    DATA(lv_json) = |'\{"status":"updated","name":"{ iv_name }","type":"dtel"\}'|.
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
      send_error( iv_status = 404 iv_message = |Structure/Table { iv_name } not found| ).
      RETURN.
    ENDIF.

    " Only return if it's a structure (not a transparent table)
    IF ls_dd02v-tabart IS NOT INITIAL.
      send_error( iv_status = 400 iv_message = |{ iv_name } is a table, use /tabl/ endpoint| ).
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

    " TODO: parse fields array from JSON body into lt_dd03p

    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING
        name      = lv_objname
        dd02v_wa  = ls_dd02v
      TABLES
        dd03p_tab = lt_dd03p
      EXCEPTIONS
        OTHERS    = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to create structure { lv_name }: sy-subrc={ sy-subrc }| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    DATA(lv_json) = |'\{"status":"created","name":"{ lv_name }","type":"stru"\}'|.
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
      send_error( iv_status = 404 iv_message = |Structure { iv_name } not found| ).
      RETURN.
    ENDIF.

    DATA(lo_data) = json_decode( iv_json ).
    DATA(lv_desc) = get_string( io_data = lo_data iv_field = 'description' ).
    IF lv_desc IS NOT INITIAL.
      ls_dd02v-ddtext = lv_desc.
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
      send_error( iv_status = 500 iv_message = |Failed to update structure { iv_name }| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    DATA(lv_json) = |'\{"status":"updated","name":"{ iv_name }","type":"stru"\}'|.
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
      send_error( iv_status = 404 iv_message = |Table { iv_name } not found| ).
      RETURN.
    ENDIF.

    " Only return if it's a transparent table
    IF ls_dd02v-tabclass <> 'TRANSP'.
      send_error( iv_status = 400 iv_message = |{ iv_name } is not a transparent table (class={ ls_dd02v-tabclass })| ).
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

    " TODO: parse fields array from JSON body into lt_dd03p

    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING
        name      = lv_objname
        dd02v_wa  = ls_dd02v
      TABLES
        dd03p_tab = lt_dd03p
      EXCEPTIONS
        OTHERS    = 6.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to create table { lv_name }: sy-subrc={ sy-subrc }| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    DATA(lv_json) = |'\{"status":"created","name":"{ lv_name }","type":"tabl"\}'|.
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
      send_error( iv_status = 404 iv_message = |Table { iv_name } not found| ).
      RETURN.
    ENDIF.

    DATA(lo_data) = json_decode( iv_json ).
    DATA(lv_desc) = get_string( io_data = lo_data iv_field = 'description' ).
    IF lv_desc IS NOT INITIAL.
      ls_dd02v-ddtext = lv_desc.
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
      send_error( iv_status = 500 iv_message = |Failed to update table { iv_name }| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name   = lv_objname
      IMPORTING
        rc     = lv_subrc
      EXCEPTIONS
        OTHERS = 1.

    DATA(lv_json) = |'\{"status":"updated","name":"{ iv_name }","type":"tabl"\}'|.
    send_json_response( iv_status = 200 iv_json = lv_json ).
  ENDMETHOD.


  METHOD json_decode.
    " Use /ui2/cl_json for JSON parsing (available in NW 7.50+)
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
    DATA(lv_json) = |\{"error":"{ iv_message }"\}|.
    send_json_response( iv_status = iv_status iv_json = lv_json ).
  ENDMETHOD.


  METHOD build_domain_json.
    " Build a simple JSON string for domain info
    DATA: lv_fixed_json TYPE string.

    LOOP AT it_dd07v INTO DATA(ls_fv).
      IF lv_fixed_json IS NOT INITIAL.
        lv_fixed_json = lv_fixed_json && ','.
      ENDIF.
      lv_fixed_json = lv_fixed_json &&
        |\{"low":"{ ls_fv-domvalue_l }","high":"{ ls_fv-domvalue_h }","text":"{ ls_fv-ddtext }"\}|.
    ENDLOOP.

    rv_json = |\{| &
      |"name":"{ iv_name }",| &
      |"type":"doma",| &
      |"description":"{ is_dd01v-ddtext }",| &
      |"datatype":"{ is_dd01v-datatype }",| &
      |"length":{ is_dd01v-leng },| &
      |"decimals":{ is_dd01v-decimals },| &
      |"fixedValues":[{ lv_fixed_json }]| &
      |\}|.
  ENDMETHOD.


  METHOD build_dtel_json.
    rv_json = |\{| &
      |"name":"{ iv_name }",| &
      |"type":"dtel",| &
      |"description":"{ is_dd04v-ddtext }",| &
      |"domain":"{ is_dd04v-domname }",| &
      |"datatype":"{ is_dd04v-datatype }",| &
      |"length":{ is_dd04v-leng },| &
      |"decimals":{ is_dd04v-decimals },| &
      |"shortLabel":"{ is_dd04v-scrtext_s }",| &
      |"mediumLabel":"{ is_dd04v-scrtext_m }",| &
      |"longLabel":"{ is_dd04v-scrtext_l }"| &
      |\}|.
  ENDMETHOD.


  METHOD build_structure_json.
    DATA: lv_fields_json TYPE string.

    LOOP AT it_dd03p INTO DATA(ls_field).
      IF lv_fields_json IS NOT INITIAL.
        lv_fields_json = lv_fields_json && ','.
      ENDIF.
      lv_fields_json = lv_fields_json &&
        |\{"name":"{ ls_field-fieldname }","key":{ COND string( WHEN ls_field-keyflag = abap_true THEN 'true' ELSE 'false' ) },| &
        |"datatype":"{ ls_field-datatype }","length":{ ls_field-leng },"decimals":{ ls_field-decimals },| &
        |"rollname":"{ ls_field-rollname }","domname":"{ ls_field-domname }","description":"{ ls_field-ddtext }"\}|.
    ENDLOOP.

    rv_json = |\{| &
      |"name":"{ iv_name }",| &
      |"type":"{ COND string( WHEN is_dd02v-tabclass = 'TRANSP' THEN 'tabl' ELSE 'stru' ) }",| &
      |"description":"{ is_dd02v-ddtext }",| &
      |"tableClass":"{ is_dd02v-tabclass }",| &
      |"fields":[{ lv_fields_json }]| &
      |\}|.
  ENDMETHOD.

ENDCLASS.
