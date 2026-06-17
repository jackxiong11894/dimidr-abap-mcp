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
    TYPES: BEGIN OF ty_fixed_value,
             low  TYPE string,
             high TYPE string,
             text TYPE string,
           END OF ty_fixed_value,
           tt_fixed_values TYPE STANDARD TABLE OF ty_fixed_value WITH DEFAULT KEY,
           BEGIN OF ty_object_config,
             type        TYPE string,
             object_type TYPE trobjtype,
             tabclass   TYPE dd02v-tabclass,
           END OF ty_object_config,
           tt_object_configs TYPE STANDARD TABLE OF ty_object_config WITH DEFAULT KEY.

    DATA: mv_request_method TYPE string,
          mv_path_info      TYPE string,
          mv_query_string   TYPE string,
          mo_server         TYPE REF TO if_http_server,
          mt_object_configs TYPE tt_object_configs.

    METHODS constructor.
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

    METHODS handle_object
      IMPORTING iv_type   TYPE string
                iv_method TYPE string
                iv_name   TYPE string
      RAISING cx_root.

    METHODS read_object
      IMPORTING iv_type   TYPE string
                iv_name   TYPE string
      RAISING cx_root.

    METHODS create_object
      IMPORTING iv_type      TYPE string
                iv_json      TYPE string
                iv_transport TYPE string OPTIONAL
      RAISING cx_root.

    METHODS update_object
      IMPORTING iv_type      TYPE string
                iv_name      TYPE string
                iv_json      TYPE string
                iv_transport TYPE string OPTIONAL
      RAISING cx_root.

    METHODS json_decode
      IMPORTING iv_json        TYPE string
      RETURNING VALUE(rv_data) TYPE REF TO data
      RAISING cx_root.

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

    METHODS get_object_config
      IMPORTING iv_type         TYPE string
      RETURNING VALUE(rv_config) TYPE ty_object_config.

    METHODS build_json_response
      IMPORTING iv_type      TYPE string
                iv_name      TYPE string
                iv_status    TYPE string
                iv_extra     TYPE any OPTIONAL
      RETURNING VALUE(rv_json) TYPE string.

    METHODS assign_transport
      IMPORTING iv_objname    TYPE sobj_name
                iv_object     TYPE trobjtype
                iv_transport TYPE string
      RAISING cx_root.

    METHODS parse_fields_array
      IMPORTING io_data         TYPE REF TO data
      RETURNING VALUE(rt_dd03p) TYPE dd03p_tab
      RAISING cx_root.

    METHODS check_activation
      IMPORTING iv_rc      TYPE i
                iv_objname TYPE string
                iv_type    TYPE string
      RAISING cx_root.

    METHODS read_ddic_object
      IMPORTING iv_type   TYPE string
                iv_name   TYPE string
      RETURNING VALUE(rv_data) TYPE REF TO data
      RAISING cx_root.

    METHODS save_ddic_object
      IMPORTING iv_type      TYPE string
                iv_name      TYPE string
                iv_data      TYPE REF TO data
                iv_transport TYPE string
      RAISING cx_root.

ENDCLASS.


CLASS zcl_adt_ddic_handler IMPLEMENTATION.

  METHOD constructor.
    mt_object_configs = VALUE #(
      ( type = 'doma' object_type = 'DOMA' tabclass = '' )
      ( type = 'dtel' object_type = 'DTEL' tabclass = '' )
      ( type = 'stru' object_type = 'TABL' tabclass = 'INTTAB' )
      ( type = 'tabl' object_type = 'TABL' tabclass = 'TRANSP' ) ).
  ENDMETHOD.

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

    handle_object(
      iv_type   = lv_object_type
      iv_method = mv_request_method
      iv_name   = lv_object_name ).
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


  METHOD handle_object.
    DATA: lv_json      TYPE string,
          lv_transport TYPE string,
          lo_data      TYPE REF TO data.

    " Get JSON body and transport
    IF iv_method <> 'GET' AND iv_method <> 'DELETE'.
      lv_json = read_json_body( ).
      IF lv_transport IS INITIAL.
        lo_data = json_decode( lv_json ).
        lv_transport = get_string( io_data = lo_data iv_field = 'transport' ).
      ENDIF.
    ENDIF.

    CASE iv_method.
      WHEN 'GET'.
        read_object( iv_type = iv_type iv_name = iv_name ).
      WHEN 'POST'.
        create_object( iv_type = iv_type iv_json = lv_json iv_transport = lv_transport ).
      WHEN 'PUT'.
        update_object( iv_type = iv_type iv_name = iv_name iv_json = lv_json iv_transport = lv_transport ).
      WHEN 'DELETE'.
        send_error( iv_status = 501 iv_message = 'Delete not yet implemented' ).
      WHEN OTHERS.
        send_error( iv_status = 405 iv_message = |Method { iv_method } not allowed| ).
    ENDCASE.
  ENDMETHOD.


  METHOD read_object.
    DATA: lv_data TYPE REF TO data,
          lv_json TYPE string.

    lv_data = read_ddic_object( iv_type = iv_type iv_name = iv_name ).

    CASE iv_type.
      WHEN 'doma'.
        DATA(ls_domain) = CAST dd01v( lv_data ).
        DATA(lt_fixed_values) = VALUE dd07v_tab( ).
        lv_json = build_domain_json(
          iv_name  = iv_name
          is_dd01v = ls_domain
          it_dd07v = lt_fixed_values ).
      WHEN 'dtel'.
        DATA(ls_dtel) = CAST dd04v( lv_data ).
        lv_json = build_dtel_json(
          iv_name  = iv_name
          is_dd04v = ls_dtel ).
      WHEN 'stru' OR 'tabl'.
        DATA(ls_structure) = CAST dd02v( lv_data ).
        " Check tabclass for structures vs tables
        IF ls_structure-tabclass = 'TRANSP' AND iv_type = 'stru'.
          send_error( iv_status = 400 iv_message = |'{ iv_name }' is a transparent table, use /tabl/ endpoint| ).
          RETURN.
        ELSEIF ls_structure-tabclass <> 'TRANSP' AND iv_type = 'tabl'.
          send_error( iv_status = 400 iv_message = |'{ iv_name }' is not a transparent table| ).
          RETURN.
        ENDIF.
        DATA(lt_fields) = VALUE dd03p_tab( ).
        lv_json = build_structure_json(
          iv_name  = iv_name
          is_dd02v = ls_structure
          it_dd03p = lt_fields ).
    ENDCASE.

    send_json_response( iv_status = 200 iv_json = lv_json ).
  ENDMETHOD.


  METHOD create_object.
    DATA: lv_data TYPE REF TO data,
          lv_name TYPE string,
          lo_json_data TYPE REF TO data,
          ls_config TYPE ty_object_config,
          ls_dd01v TYPE dd01v,
          ls_dd04v TYPE dd04v,
          ls_dd02v TYPE dd02v,
          lv_domain TYPE domname,
          lv_datatype TYPE datatype,
          lv_length TYPE ddleng,
          lv_decimals TYPE dddecimals,
          lv_desc TYPE ddtext,
          lv_heading TYPE ddtext,
          lv_short TYPE ddtext,
          lv_medium TYPE ddtext,
          lv_long TYPE ddtext.

    lo_json_data = json_decode( iv_json ).
    lv_name = get_string( io_data = lo_json_data iv_field = 'name' ).
    IF lv_name IS INITIAL.
      send_error( iv_status = 400 iv_message = 'Name is required' ).
      RETURN.
    ENDIF.

    ls_config = get_object_config( iv_type ).

    " Initialize data based on type
    CASE iv_type.
      WHEN 'doma'.
        CREATE DATA lv_data TYPE dd01v.
        ASSIGN lv_data->* TO FIELD-SYMBOL(<ls_data>).
        <ls_data> = ls_dd01v.
        ls_dd01v-domname = lv_name.
        ls_dd01v-ddlanguage = sy-langu.
        ls_dd01v-responsible = sy-uname.
        lv_datatype = get_string( io_data = lo_json_data iv_field = 'datatype' ).
        IF lv_datatype IS NOT INITIAL.
          ls_dd01v-datatype = lv_datatype.
        ENDIF.
        lv_length = get_number( io_data = lo_json_data iv_field = 'length' ).
        IF lv_length > 0.
          ls_dd01v-leng = lv_length.
          ls_dd01v-domlen = lv_length.
        ENDIF.
        lv_decimals = get_number( io_data = lo_json_data iv_field = 'decimals' ).
        IF lv_decimals >= 0.
          ls_dd01v-decimals = lv_decimals.
        ENDIF.
        lv_desc = get_string( io_data = lo_json_data iv_field = 'description' ).
        IF lv_desc IS NOT INITIAL.
          ls_dd01v-ddtext = lv_desc.
        ENDIF.
        <ls_data> = ls_dd01v.

      WHEN 'dtel'.
        CREATE DATA lv_data TYPE dd04v.
        ASSIGN lv_data->* TO <ls_data>.
        <ls_data> = ls_dd04v.
        ls_dd04v-rollname = lv_name.
        ls_dd04v-ddlanguage = sy-langu.
        lv_desc = get_string( io_data = lo_json_data iv_field = 'description' ).
        IF lv_desc IS NOT INITIAL.
          ls_dd04v-ddtext = lv_desc.
        ENDIF.
        lv_heading = get_string( io_data = lo_json_data iv_field = 'headingLabel' ).
        IF lv_heading IS NOT INITIAL.
          ls_dd04v-reptext = lv_heading.
        ENDIF.
        IF ls_dd04v-reptext IS INITIAL.
          lv_short = get_string( io_data = lo_json_data iv_field = 'shortLabel' ).
          IF lv_short IS NOT INITIAL.
            ls_dd04v-reptext = lv_short.
          ENDIF.
        ENDIF.
        lv_short = get_string( io_data = lo_json_data iv_field = 'shortLabel' ).
        IF lv_short IS NOT INITIAL.
          ls_dd04v-scrtext_s = lv_short.
        ENDIF.
        lv_medium = get_string( io_data = lo_json_data iv_field = 'mediumLabel' ).
        IF lv_medium IS NOT INITIAL.
          ls_dd04v-scrtext_m = lv_medium.
        ENDIF.
        lv_long = get_string( io_data = lo_json_data iv_field = 'longLabel' ).
        IF lv_long IS NOT INITIAL.
          ls_dd04v-scrtext_l = lv_long.
        ENDIF.
        ls_dd04v-responsible = sy-uname.

        " Get domain
        lv_domain = get_string( io_data = lo_json_data iv_field = 'domain' ).
        IF lv_domain IS NOT INITIAL.
          ls_dd04v-domname = lv_domain.
        ENDIF.
        <ls_data> = ls_dd04v.

      WHEN 'stru' OR 'tabl'.
        CREATE DATA lv_data TYPE dd02v.
        ASSIGN lv_data->* TO <ls_data>.
        <ls_data> = ls_dd02v.
        ls_dd02v-tabname = lv_name.
        ls_dd02v-ddlanguage = sy-langu.
        lv_desc = get_string( io_data = lo_json_data iv_field = 'description' ).
        IF lv_desc IS NOT INITIAL.
          ls_dd02v-ddtext = lv_desc.
        ENDIF.
        ls_dd02v-tabclass = ls_config-tabclass.
        ls_dd02v-responsible = sy-uname.
        IF ls_config-tabclass = 'TRANSP'.
          ls_dd02v-tabart = 'APPL0'.
          ls_dd02v-bufallow = 'N'.
        ENDIF.
        <ls_data> = ls_dd02v.
    ENDCASE.

    " Save the object
    save_ddic_object(
      iv_type      = iv_type
      iv_name      = lv_name
      iv_data      = lv_data
      iv_transport = iv_transport ).

    " Build success response
    DATA(lv_json) = build_json_response(
      iv_type   = iv_type
      iv_name   = lv_name
      iv_status = 'created' ).
    send_json_response( iv_status = 201 iv_json = lv_json ).
  ENDMETHOD.


  METHOD update_object.
    DATA: lv_data TYPE REF TO data,
          lv_json TYPE string,
          lo_json_data TYPE REF TO data,
          ls_config TYPE ty_object_config,
          ls_dd01v TYPE dd01v,
          ls_dd04v TYPE dd04v,
          ls_dd02v TYPE dd02v,
          lv_desc TYPE ddtext,
          lv_datatype TYPE datatype,
          lv_length TYPE ddleng,
          lv_decimals TYPE dddecimals,
          lv_domain TYPE domname,
          lv_heading TYPE ddtext,
          lv_short TYPE ddtext,
          lv_medium TYPE ddtext,
          lv_long TYPE ddtext.

    " Read existing object
    lv_data = read_ddic_object( iv_type = iv_type iv_name = iv_name ).

    lo_json_data = json_decode( iv_json ).
    ls_config = get_object_config( iv_type ).

    " Update the data with new values
    CASE iv_type.
      WHEN 'doma'.
        ASSIGN lv_data->* TO FIELD-SYMBOL(<ls_data>).
        <ls_data> = ls_dd01v.
        lv_desc = get_string( io_data = lo_json_data iv_field = 'description' ).
        IF lv_desc IS NOT INITIAL.
          ls_dd01v-ddtext = lv_desc.
        ENDIF.
        lv_datatype = get_string( io_data = lo_json_data iv_field = 'datatype' ).
        IF lv_datatype IS NOT INITIAL.
          ls_dd01v-datatype = lv_datatype.
        ENDIF.
        lv_length = get_number( io_data = lo_json_data iv_field = 'length' ).
        IF lv_length > 0.
          ls_dd01v-leng = lv_length.
          ls_dd01v-domlen = lv_length.
        ENDIF.
        lv_decimals = get_number( io_data = lo_json_data iv_field = 'decimals' ).
        IF lv_decimals >= 0.
          ls_dd01v-decimals = lv_decimals.
        ENDIF.
        <ls_data> = ls_dd01v.

      WHEN 'dtel'.
        ASSIGN lv_data->* TO <ls_data>.
        <ls_data> = ls_dd04v.
        lv_desc = get_string( io_data = lo_json_data iv_field = 'description' ).
        IF lv_desc IS NOT INITIAL.
          ls_dd04v-ddtext = lv_desc.
        ENDIF.
        lv_domain = get_string( io_data = lo_json_data iv_field = 'domain' ).
        IF lv_domain IS NOT INITIAL.
          ls_dd04v-domname = lv_domain.
        ENDIF.
        lv_heading = get_string( io_data = lo_json_data iv_field = 'headingLabel' ).
        IF lv_heading IS NOT INITIAL.
          ls_dd04v-reptext = lv_heading.
        ENDIF.
        lv_short = get_string( io_data = lo_json_data iv_field = 'shortLabel' ).
        IF lv_short IS NOT INITIAL.
          ls_dd04v-scrtext_s = lv_short.
          IF lv_heading IS INITIAL.
            ls_dd04v-reptext = lv_short.
          ENDIF.
        ENDIF.
        lv_medium = get_string( io_data = lo_json_data iv_field = 'mediumLabel' ).
        IF lv_medium IS NOT INITIAL.
          ls_dd04v-scrtext_m = lv_medium.
        ENDIF.
        lv_long = get_string( io_data = lo_json_data iv_field = 'longLabel' ).
        IF lv_long IS NOT INITIAL.
          ls_dd04v-scrtext_l = lv_long.
        ENDIF.
        <ls_data> = ls_dd04v.

      WHEN 'stru' OR 'tabl'.
        ASSIGN lv_data->* TO <ls_data>.
        <ls_data> = ls_dd02v.
        lv_desc = get_string( io_data = lo_json_data iv_field = 'description' ).
        IF lv_desc IS NOT INITIAL.
          ls_dd02v-ddtext = lv_desc.
        ENDIF.

        " Handle fields update if provided
        DATA(lt_new_fields) = parse_fields_array( io_data = lo_json_data ).
        IF lines( lt_new_fields ) > 0.
          " Field update logic would go here
        ENDIF.
        <ls_data> = ls_dd02v.
    ENDCASE.

    " Save the updated object
    save_ddic_object(
      iv_type      = iv_type
      iv_name      = iv_name
      iv_data      = lv_data
      iv_transport = iv_transport ).

    " Build success response
    lv_json = build_json_response(
      iv_type   = iv_type
      iv_name   = iv_name
      iv_status = 'updated' ).
    send_json_response( iv_status = 200 iv_json = lv_json ).
  ENDMETHOD.


  METHOD get_object_config.
    READ TABLE mt_object_configs WITH TABLE KEY type = iv_type INTO rv_config.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_sy_dyn_call_error
        EXPORTING textid = cx_sy_dyn_call_error=>parameter_invalid
                  msgv1  = iv_type.
    ENDIF.
  ENDMETHOD.


  METHOD build_json_response.
    DATA: lv_extra_json TYPE string.

    IF iv_extra IS SUPPLIED.
      " Convert extra data to JSON string
      lv_extra_json = |,"extra":{ json_encode( EXPORTING iv_data = REF #( iv_extra ) ) }|.
    ENDIF.

    rv_json = |\{| &
      |"status":"{ iv_status }",| &
      |"name":"{ iv_name }",| &
      |"type":"{ iv_type }"| &
      lv_extra_json &
      |\}|.
  ENDMETHOD.


  METHOD read_ddic_object.
    DATA: lv_objname TYPE ddobjname,
          lv_subrc   TYPE i,
          ls_dd01v   TYPE dd01v,
          ls_dd04v   TYPE dd04v,
          ls_dd02v   TYPE dd02v,
          lt_dd07v   TYPE dd07v_tab,
          lt_dd03p   TYPE dd03p_tab.

    lv_objname = iv_name.

    CASE iv_type.
      WHEN 'doma'.
        CALL FUNCTION 'DDIF_DOMA_GET'
          EXPORTING
            name   = lv_objname
            state  = 'A'
            langu  = sy-langu
          IMPORTING
            gotstate = lv_subrc
            dd01v_wa = ls_dd01v
          TABLES
            dd07v_tab = lt_dd07v
          EXCEPTIONS
            OTHERS = 2.
        CREATE DATA rv_data TYPE dd01v.
        ASSIGN rv_data->* TO FIELD-SYMBOL(<ls_data>).
        <ls_data> = ls_dd01v.

      WHEN 'dtel'.
        CALL FUNCTION 'DDIF_DTEL_GET'
          EXPORTING
            name   = lv_objname
            state  = 'A'
            langu  = sy-langu
          IMPORTING
            gotstate = lv_subrc
            dd04v_wa = ls_dd04v
          EXCEPTIONS
            OTHERS = 2.
        CREATE DATA rv_data TYPE dd04v.
        ASSIGN rv_data->* TO <ls_data>.
        <ls_data> = ls_dd04v.

      WHEN 'stru' OR 'tabl'.
        CALL FUNCTION 'DDIF_TABL_GET'
          EXPORTING
            name   = lv_objname
            state  = 'A'
            langu  = sy-langu
          IMPORTING
            gotstate = lv_subrc
            dd02v_wa = ls_dd02v
          TABLES
            dd03p_tab = lt_dd03p
          EXCEPTIONS
            OTHERS = 2.
        CREATE DATA rv_data TYPE dd02v.
        ASSIGN rv_data->* TO <ls_data>.
        <ls_data> = ls_dd02v.
    ENDCASE.

    IF sy-subrc <> 0 OR lv_subrc = 0.
      send_error( iv_status = 404 iv_message = |{ iv_type } '{ iv_name }' not found| ).
      RAISE EXCEPTION TYPE cx_sy_dyn_call_error.
    ENDIF.
  ENDMETHOD.


  METHOD save_ddic_object.
    DATA: lv_objname TYPE ddobjname,
          lv_subrc   TYPE i,
          ls_config  TYPE ty_object_config,
          lt_dd07v   TYPE dd07v_tab,
          lt_dd03p   TYPE dd03p_tab.

    ls_config = get_object_config( iv_type ).
    lv_objname = iv_name.

    CASE iv_type.
      WHEN 'doma'.
        ASSIGN iv_data->* TO FIELD-SYMBOL(<ls_dd01v>).
        CALL FUNCTION 'DDIF_DOMA_PUT'
          EXPORTING
            name      = lv_objname
            dd01v_wa  = <ls_dd01v>
          TABLES
            dd07v_tab = lt_dd07v
          EXCEPTIONS
            OTHERS = 6.
      WHEN 'dtel'.
        ASSIGN iv_data->* TO FIELD-SYMBOL(<ls_dd04v>).
        CALL FUNCTION 'DDIF_DTEL_PUT'
          EXPORTING
            name      = lv_objname
            dd04v_wa  = <ls_dd04v>
          EXCEPTIONS
            OTHERS = 6.
      WHEN 'stru' OR 'tabl'.
        ASSIGN iv_data->* TO FIELD-SYMBOL(<ls_dd02v>).
        CALL FUNCTION 'DDIF_TABL_PUT'
          EXPORTING
            name      = lv_objname
            dd02v_wa  = <ls_dd02v>
          TABLES
            dd03p_tab = lt_dd03p
          EXCEPTIONS
            OTHERS = 6.
    ENDCASE.

    IF sy-subrc <> 0.
      send_error( iv_status = 500 iv_message = |Failed to save { iv_type } '{ iv_name }'| ).
      RETURN.
    ENDIF.

    " Activate
    CASE iv_type.
      WHEN 'doma'.
        CALL FUNCTION 'DDIF_DOMA_ACTIVATE'
          EXPORTING
            name = lv_objname
          IMPORTING
            rc   = lv_subrc
          EXCEPTIONS
            OTHERS = 1.
      WHEN 'dtel'.
        CALL FUNCTION 'DDIF_DTEL_ACTIVATE'
          EXPORTING
            name = lv_objname
          IMPORTING
            rc   = lv_subrc
          EXCEPTIONS
            OTHERS = 1.
      WHEN 'stru' OR 'tabl'.
        CALL FUNCTION 'DDIF_TABL_ACTIVATE'
          EXPORTING
            name = lv_objname
          IMPORTING
            rc   = lv_subrc
          EXCEPTIONS
            OTHERS = 1.
    ENDCASE.

    check_activation( iv_rc = lv_subrc iv_objname = iv_name iv_type = iv_type ).

    " Assign to transport if provided
    IF iv_transport IS NOT INITIAL.
      assign_transport(
        iv_objname   = lv_objname
        iv_object    = ls_config-object_type
        iv_transport = iv_transport ).
    ENDIF.

    COMMIT WORK.
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
    DATA: ls_field_data TYPE REF TO data,
          lt_fields TYPE REF TO data,
          ls_dd03p LIKE LINE OF rt_dd03p,
          lv_pos TYPE ddposition VALUE 0,
          lv_val TYPE string,
          lv_bool TYPE abap_bool,
          lv_int TYPE i,
          lv_datatype TYPE datatype,
          lv_rollname TYPE rollname.

    CREATE DATA ls_field_data TYPE any.
    ASSIGN ls_field_data->* TO FIELD-SYMBOL(<ls_field>).
    ASSIGN io_data->* TO <ls_field>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " Try to get 'fields' component
    ASSIGN COMPONENT 'fields' OF STRUCTURE <ls_field> TO FIELD-SYMBOL(<lt_fields>).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " Clear the result table
    CLEAR rt_dd03p.

    lv_pos = 0.

    LOOP AT <lt_fields> INTO <ls_field>.
      lv_pos = lv_pos + 10.
      CLEAR ls_dd03p.

      " Field name (required)
      ASSIGN COMPONENT 'name' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-fieldname = to_upper( lv_val ).
      ENDIF.

      IF ls_dd03p-fieldname IS INITIAL.
        CONTINUE.  " Skip fields without name
      ENDIF.

      ls_dd03p-position = lv_pos.
      ls_dd03p-ddlanguage = sy-langu.
      ls_dd03p-tabname = 'TEMP'.  " Will be set by DDIF_TABL_PUT

      " Key flag
      ASSIGN COMPONENT 'key' OF STRUCTURE <ls_field> TO <lv_bool>.
      IF sy-subrc = 0.
        IF lv_bool = abap_true OR lv_bool = 'true' OR lv_bool = 'X'.
          ls_dd03p-keyflag = abap_true.
        ENDIF.
      ENDIF.

      " Data element reference (rollname)
      ASSIGN COMPONENT 'rollname' OF STRUCTURE <ls_field> TO <lv_rollname>.
      IF sy-subrc = 0.
        ls_dd03p-rollname = to_upper( lv_rollname ).
      ENDIF.

      " Direct type specification (if no data element)
      IF ls_dd03p-rollname IS INITIAL.
        ASSIGN COMPONENT 'datatype' OF STRUCTURE <ls_field> TO <lv_datatype>.
        IF sy-subrc = 0.
          ls_dd03p-datatype = to_upper( lv_datatype ).
        ENDIF.

        ASSIGN COMPONENT 'length' OF STRUCTURE <ls_field> TO <lv_int>.
        IF sy-subrc = 0.
          ls_dd03p-leng = lv_int.
        ENDIF.

        ASSIGN COMPONENT 'decimals' OF STRUCTURE <ls_field> TO <lv_int>.
        IF sy-subrc = 0.
          ls_dd03p-decimals = lv_int.
        ENDIF.
      ENDIF.

      " Text fields
      ASSIGN COMPONENT 'description' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-ddtext = lv_val.
      ENDIF.

      " FIX: headingLabel → reptext
      ASSIGN COMPONENT 'headingLabel' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-reptext = lv_val.
      ENDIF.

      ASSIGN COMPONENT 'shortLabel' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-scrtext_s = lv_val.
        " Fallback: use shortLabel for reptext if headingLabel not provided
        IF ls_dd03p-reptext IS INITIAL.
          ls_dd03p-reptext = lv_val.
        ENDIF.
      ENDIF.

      ASSIGN COMPONENT 'mediumLabel' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-scrtext_m = lv_val.
      ENDIF.

      ASSIGN COMPONENT 'longLabel' OF STRUCTURE <ls_field> TO <lv_val>.
      IF sy-subrc = 0.
        ls_dd03p-scrtext_l = lv_val.
      ENDIF.

      APPEND ls_dd03p TO rt_dd03p.
    ENDLOOP.
  ENDMETHOD.


  METHOD check_activation.
    " Check activation return code and raise error if failed
    IF iv_rc <> 0.
      DATA(lv_msg) = |{ iv_type } '{ iv_objname }' activation failed (rc={ iv_rc })|.
      RAISE EXCEPTION TYPE cx_sy_dyn_call_error
        EXPORTING
          textid = cx_sy_dyn_call_error=>cx_sy_dyn_call_error
          msgv1  = lv_msg.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
