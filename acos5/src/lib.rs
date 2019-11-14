/*
 * lib.rs: Driver 'acos5' - main library file
 *
 * Copyright (C) 2019  Carsten Blüggel <bluecars@posteo.eu>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, 51 Franklin Street, Fifth Floor  Boston, MA 02110-1335  USA
 */
/*
 https://www.acs.com.hk/en/products/18/cryptomate64-usb-cryptographic-tokens/

 https://www.acs.com.hk/en/products/308/acos5-64-v3.00-cryptographic-card-contact/
 https://www.acs.com.hk/en/products/414/cryptomate-nano-cryptographic-usb-tokens/
 https://www.acs.com.hk/en/products/464/acos5-evo-pki-smart-card-contact/

 https://help.github.com/en/articles/changing-a-remotes-url

 Table 4 - Data within a command-response pair : APDU case
Case     Command data     Expected response data
1         No data             No data
2         No data             Data
3         Data                No data
4         Data                Data

 TODO Many error returns are provisorily set to SC_ERROR_KEYPAD_MSG_TOO_LONG to be refined later
 TODO Only set to anything other than SC_ERROR_KEYPAD_MSG_TOO_LONG, if that's the final setting
#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
*/

//#![feature(const_fn)]
//#![feature(ptr_offset_from)]


#![cfg_attr(feature = "cargo-clippy", warn(clippy::all))]
#![cfg_attr(feature = "cargo-clippy", warn(clippy::pedantic))]

#![cfg_attr(feature = "cargo-clippy", allow(clippy::doc_markdown))]
#![cfg_attr(feature = "cargo-clippy", allow(clippy::similar_names))]
#![cfg_attr(feature = "cargo-clippy", allow(clippy::cognitive_complexity))]

//#![cfg_attr(feature = "cargo-clippy", allow(clippy::cast_lossless))]
#![cfg_attr(feature = "cargo-clippy", allow(clippy::module_name_repetitions))]
#![cfg_attr(feature = "cargo-clippy", allow(clippy::if_not_else))]
//#![cfg_attr(feature = "cargo-clippy", allow(clippy::unseparated_literal_suffix))]
//#![cfg_attr(feature = "cargo-clippy", allow(clippy::use_self))]
//#![cfg_attr(feature = "cargo-clippy", allow(clippy::default_trait_access))]
#![cfg_attr(feature = "cargo-clippy", allow(clippy::shadow_unrelated))]
#![cfg_attr(feature = "cargo-clippy", allow(clippy::cast_possible_truncation))]
#![cfg_attr(feature = "cargo-clippy", allow(clippy::cast_sign_loss))]
#![cfg_attr(feature = "cargo-clippy", allow(clippy::cast_possible_wrap))]


extern crate libc;
extern crate num_integer;
extern crate iso7816_tlv;
//extern crate tlv_parser;
extern crate opensc_sys;
//extern crate bitintr; //no_cdecl.rs
//extern crate ring;
//use ring::digest::{/*Context, Digest,*/ digest, SHA256/*, Algorithm, Context*/};

//extern crate data_encoding;
//use data_encoding::HEXUPPER;

use std::os::raw::{c_int, c_uint, c_void, c_char, c_uchar, c_ulong/*, c_ushort*/};
use std::ffi::CStr;
use std::ptr::{copy_nonoverlapping, null_mut, null};
use std::collections::HashMap;
use std::slice::from_raw_parts;
//use std::fs;

use opensc_sys::opensc::{sc_card, sc_card_driver, sc_card_operations, sc_security_env, sc_pin_cmd_data,
                         sc_get_iso7816_driver, sc_file_add_acl_entry, sc_format_path, sc_file_set_prop_attr,
                         sc_transmit_apdu, sc_bytes2apdu_wrapper, sc_check_sw, SC_CARD_CAP_RNG, SC_CARD_CAP_USE_FCI_AC,
                         SC_READER_SHORT_APDU_MAX_SEND_SIZE, SC_READER_SHORT_APDU_MAX_RECV_SIZE, SC_ALGORITHM_RSA,
                         SC_ALGORITHM_ONBOARD_KEY_GEN, SC_ALGORITHM_RSA_RAW, SC_SEC_OPERATION_SIGN,
                         SC_SEC_OPERATION_DECIPHER, SC_SEC_ENV_FILE_REF_PRESENT, SC_SEC_OPERATION_DERIVE,
                         SC_PIN_CMD_GET_INFO, SC_PIN_CMD_VERIFY, SC_PIN_CMD_CHANGE, SC_PIN_CMD_UNBLOCK,
                         SC_ALGORITHM_RSA_PAD_PKCS1, SC_ALGORITHM_RSA_PAD_ISO9796, SC_ALGORITHM_RSA_HASH_NONE,
                         SC_SEC_ENV_KEY_REF_PRESENT, SC_SEC_ENV_ALG_REF_PRESENT, SC_SEC_ENV_ALG_PRESENT,
                         SC_ALGORITHM_3DES, SC_ALGORITHM_DES, SC_RECORD_BY_REC_NR, sc_select_file,
                         SC_CARD_CAP_ISO7816_PIN_INFO, SC_ALGORITHM_AES, sc_file_free, sc_read_binary,
                         SC_ALGORITHM_ECDSA_RAW, SC_ALGORITHM_EXT_EC_NAMEDCURVE//, sc_path_set
//                         SC_ALGORITHM_ECDH_CDH_RAW, SC_ALGORITHM_ECDSA_HASH_NONE, SC_ALGORITHM_ECDSA_HASH_SHA1,
//                         SC_ALGORITHM_EXT_EC_UNCOMPRESES,
//                         sc_pin_cmd_pin, sc_pin_cmd, sc_update_binary, sc_verify,
};
#[cfg(not(v0_17_0))]
use opensc_sys::opensc::{SC_SEC_ENV_KEY_REF_SYMMETRIC};
//#[cfg(not(any(v0_17_0, v0_18_0)))]
//use opensc_sys::opensc::{SC_ALGORITHM_RSA_PAD_PSS};
#[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
use opensc_sys::opensc::{sc_update_record, SC_SEC_ENV_PARAM_IV, SC_SEC_ENV_PARAM_TARGET_FILE, SC_ALGORITHM_AES_FLAGS,
                         SC_ALGORITHM_AES_CBC_PAD, SC_ALGORITHM_AES_CBC, SC_ALGORITHM_AES_ECB, SC_SEC_OPERATION_UNWRAP,
                         SC_CARD_CAP_UNWRAP_KEY//, SC_CARD_CAP_WRAP_KEY
//                         , SC_SEC_OPERATION_WRAP
};

use opensc_sys::types::{sc_aid, SC_MAX_AID_SIZE, SC_AC_CHV, sc_path, sc_file, sc_serial_number, SC_MAX_PATH_SIZE,
                        SC_PATH_TYPE_FILE_ID, SC_PATH_TYPE_DF_NAME, SC_PATH_TYPE_PATH,
//                        SC_PATH_TYPE_PATH_PROT, SC_PATH_TYPE_FROM_CURRENT, SC_PATH_TYPE_PARENT,
                        SC_FILE_TYPE_DF, SC_FILE_TYPE_INTERNAL_EF, SC_FILE_EF_TRANSPARENT, SC_AC_NONE,
                        SC_AC_KEY_REF_NONE, SC_AC_OP_LIST_FILES, SC_AC_OP_SELECT, SC_AC_OP_DELETE, SC_AC_OP_CREATE_EF,
                        SC_AC_OP_CREATE_DF, SC_AC_OP_INVALIDATE, SC_AC_OP_REHABILITATE, SC_AC_OP_LOCK, SC_AC_OP_READ,
                        SC_AC_OP_UPDATE, SC_AC_OP_CRYPTO, SC_AC_OP_DELETE_SELF, SC_AC_OP_CREATE, SC_AC_OP_WRITE,
                        SC_AC_OP_GENERATE, SC_APDU_FLAGS_CHAINING, SC_APDU_FLAGS_NO_GET_RESP, SC_APDU_CASE_1,
                        SC_APDU_CASE_2_SHORT, SC_APDU_CASE_3_SHORT, SC_APDU_CASE_4_SHORT, sc_apdu};

use opensc_sys::errors::{sc_strerror, SC_SUCCESS, SC_ERROR_INTERNAL, SC_ERROR_INVALID_ARGUMENTS, SC_ERROR_KEYPAD_MSG_TOO_LONG,
                         SC_ERROR_NO_CARD_SUPPORT, SC_ERROR_INCOMPATIBLE_KEY, SC_ERROR_WRONG_CARD, SC_ERROR_WRONG_PADDING,
                         SC_ERROR_INCORRECT_PARAMETERS, SC_ERROR_NOT_SUPPORTED, SC_ERROR_BUFFER_TOO_SMALL, SC_ERROR_NOT_ALLOWED,
                         SC_ERROR_SECURITY_STATUS_NOT_SATISFIED};
use opensc_sys::internal::{_sc_card_add_rsa_alg, _sc_card_add_ec_alg, sc_pkcs1_encode, _sc_match_atr};

use opensc_sys::log::{sc_dump_hex};
use opensc_sys::cardctl::{SC_CARDCTL_GET_SERIALNR, SC_CARDCTL_LIFECYCLE_SET};
use opensc_sys::asn1::{sc_asn1_find_tag, sc_asn1_put_tag/*, sc_asn1_skip_tag, sc_asn1_read_tag, sc_asn1_print_tags*/};
use opensc_sys::iso7816::{ISO7816_TAG_FCP_TYPE, ISO7816_TAG_FCP_LCS,  ISO7816_TAG_FCP, ISO7816_TAG_FCP_SIZE,
                          ISO7816_TAG_FCP_FID, ISO7816_TAG_FCP_DF_NAME};
use opensc_sys::pkcs15::{sc_pkcs15_pubkey_rsa, sc_pkcs15_bignum, sc_pkcs15_encode_pubkey_rsa, sc_pkcs15_bind,
                         sc_pkcs15_unbind, sc_pkcs15_auth_info, sc_pkcs15_get_objects, SC_PKCS15_TYPE_AUTH_PIN,
                         sc_pkcs15_object}; // , SC_PKCS15_AODF
use opensc_sys::sm::{SM_TYPE_CWA14890};

//#[allow(dead_code)]
pub mod    cmd_card_info;
use crate::cmd_card_info::*;

pub mod    constants_types;
use crate::constants_types::*;

pub mod    crypto;

pub mod    missing_exports;
use crate::missing_exports::{me_card_add_symmetric_alg, me_card_find_alg, me_get_max_recv_size,
                             me_pkcs1_strip_01_padding, me_pkcs1_strip_02_padding};//, me_get_encoding_flags

// choose new name ? denoting, that there are rust-mangled, non-externC functions, that don't relate to se
// (security environment) nor relate to sm (secure messaging) nor relate to pkcs15/pkcs15-init
pub mod    no_cdecl;
use crate::no_cdecl::{select_file_by_path, convert_bytes_tag_fcp_sac_to_scb_array, enum_dir,
    pin_get_policy, tracking_select_file, acos5_supported_atrs,
                      /*encrypt_public_rsa,*/ get_sec_env, set_sec_env,// get_rsa_caps,
    get_is_running_cmd_long_response, set_is_running_cmd_long_response, is_any_known_digestAlgorithm,
    sym_en_decrypt,
    generate_asym, encrypt_asym, get_files_hashmap_info, update_hashmap,
    logical_xor/*, create_mf_file_system*/, convert_acl_array_to_bytes_tag_fcp_sac, get_sec_env_mod_len,
    ACL_CATEGORY_DF_MF, ACL_CATEGORY_EF_CHV, ACL_CATEGORY_KEY, ACL_CATEGORY_SE,
    get_is_running_compute_signature, set_is_running_compute_signature, manage_common_read, manage_common_update,
    common_read, common_update, acos5_supported_ec_curves
};

pub mod    path;
use crate::path::*;

pub mod    se;
use crate::se::{se_file_add_acl_entry, se_get_is_scb_suitable_for_sm_has_ct, se_parse_sae,
                se_get_sae_scb};

pub mod    sm;
use crate::sm::{sm_erase_binary, sm_delete_file, sm_pin_cmd_verify, sm_pin_cmd_get_policy};

pub mod    wrappers;
use crate::wrappers::*;


/*
#[cfg(test)]
#[cfg(test_v2_v3_token)]
mod   test_v2_v3;
*/


/*
macro_rules! offset_of {
    ($ty:ty, $field:ident) => {
        unsafe { &(*(0 as *const $ty)).$field as *const _ as usize }
    }
}
*/


/* #[no_mangle] pub extern fn  is the same as  #[no_mangle] pub extern "C" fn
   for the time being, be explicit using  #[no_mangle] pub extern "C" fn */


/// A mandatory library export  It MUST BE identical for acos5 and acos5_pkcs15
/// @apiNote  If @return doesn't match the version of OpenSC binary libopensc.so/dll installed, this library
///           will be unloaded immediately; depends on build.rs setup ref. "cargo:rustc-cfg=v0_??_0".
///
///           It's essential, that this doesn't merely echo, what a call to  sc_get_version() reports:
///           It's my/developer's statement, that the support as reported by sc_driver_version() got checked !
///           Thus, if e.g. a new OpenSC version 0.21.0 got released and if I didn't reflect that in sc_driver_version(),
///           (updating opensc-sys binding and code of acos5 and acos5_pkcs15)
///           then the driver won't accidentally work for a not yet supported OpenSC environment/version !
///
///           The support of not yet released OpenSC code (i.e. github/master) is somewhat experimental:
///           It's accuracy depends on how closely the opensc-sys binding and driver code has covered the possible
///           differences in API and behavior (it's build.rs mention the last OpenSC commit covered).
///           master will be handled as an imaginary new version release:
///           E.g. while currently the latest release is 0.19.0, build OpenSC from source such that it reports imaginary
///           version 0.20.0 (change config.h after ./configure and before make, and change opensc.pc as well)
///           In this example, cfg!(v0_20_0) will then match that
///
/// @return   The OpenSC release/imaginary version, that this driver implementation supports
#[no_mangle]
pub extern "C" fn sc_driver_version() -> *const c_char {
    if       cfg!(v0_17_0) { CStr::from_bytes_with_nul(b"0.17.0\0").unwrap().as_ptr() }
    else  if cfg!(v0_18_0) { CStr::from_bytes_with_nul(b"0.18.0\0").unwrap().as_ptr() }
    else  if cfg!(v0_19_0) { CStr::from_bytes_with_nul(b"0.19.0\0").unwrap().as_ptr() }
    else  if cfg!(v0_20_0) { CStr::from_bytes_with_nul(b"0.20.0\0").unwrap().as_ptr() }
    else                   { CStr::from_bytes_with_nul(b"0.0.0\0" ).unwrap().as_ptr() } // will definitely cause rejection by OpenSC
}

/// A mandatory library export
/// @apiNote TODO inspect behavior in multi-threading context
/// @param   name passed in by OpenSC (acc. opensc.conf: assoc. 'acos5_external' <-> ATR or card_driver acos5_external {...})
/// @return  function pointer; calling that returns acos5_external's sc_card_driver struct address
#[no_mangle]
#[cfg_attr(feature = "cargo-clippy", allow(clippy::missing_safety_doc))]
pub unsafe extern "C" fn sc_module_init(name: *const c_char) -> *mut c_void {
    if !name.is_null() && CStr::from_ptr(name) == CStr::from_bytes_with_nul(CARD_DRV_SHORT_NAME).unwrap() {
        acos5_get_card_driver as *mut c_void
    }
    else {
        null_mut::<c_void>()
    }
}


/*
 * What it does
 * @apiNote
 * @return
 */
extern "C" fn acos5_get_card_driver() -> *mut sc_card_driver
{
/*
static struct sc_card_operations iso_ops = {
    no_match,
    iso7816_init,    /* init   */
    NULL,            /* finish */
    iso7816_read_binary,
    iso7816_write_binary,
    iso7816_update_binary,
    NULL,            /* erase_binary */
    iso7816_read_record,
    iso7816_write_record,
    iso7816_append_record,
    iso7816_update_record,
    iso7816_select_file,
    iso7816_get_response,
    iso7816_get_challenge,
    NULL,            /* verify */
    NULL,            /* logout */
    iso7816_restore_security_env,
    iso7816_set_security_env,
    iso7816_decipher,
    iso7816_compute_signature,
    NULL,            /* change_reference_data */
    NULL,            /* reset_retry_counter   */
    iso7816_create_file,
    iso7816_delete_file,
    NULL,            /* list_files */
    iso7816_check_sw,
    NULL,            /* card_ctl */
    iso7816_process_fci,
    iso7816_construct_fci,
    iso7816_pin_cmd,
    iso7816_get_data,
    NULL,            /* put_data */
    NULL,            /* delete_record */
    NULL,            /* read_public_key */
    NULL,            /* card_reader_lock_obtained */
    NULL,            /* wrap */
    NULL             /* unwrap */
};
*/
    let iso_ops = unsafe { *(*sc_get_iso7816_driver()).ops };
    let b_sc_card_operations = Box::new( sc_card_operations {
        match_card:            Some(acos5_match_card),        // no_match     is insufficient for cos5: It just doesn't match any ATR
        init:                  Some(acos5_init),              // iso7816_init is insufficient for cos5: It just returns SC_SUCCESS without doing anything
        finish:                Some(acos5_finish),            // NULL
        /* ATTENTION: calling the iso7816_something_record functions requires using flag SC_RECORD_BY_REC_NR  or it won't work as expected !!! s*/
        erase_binary:          Some(acos5_erase_binary),      // NULL
        delete_record:         Some(acos5_delete_record),     // NULL
        append_record:         Some(acos5_append_record),     // iso7816_append_record

        read_binary:           Some(acos5_read_binary),       // iso7816_read_binary
        read_record:           Some(acos5_read_record),       // iso7816_read_record

        update_binary:         Some(acos5_update_binary),     // iso7816_update_binary
        write_binary:          Some(acos5_update_binary),     // iso7816_write_binary
        update_record:         Some(acos5_update_record),     // iso7816_update_record
        write_record:          Some(acos5_update_record),     // iso7816_write_record

        select_file:           Some(acos5_select_file),       // iso7816_select_file is insufficient for cos5: It will be used, but in a controlled manner only
        get_response:          Some(acos5_get_response),      // iso7816_get_response is insufficient for some cos5 commands with more than 256 bytes to fetch
            /* get_challenge:  iso7816_get_challenge  is usable, but only with P3==8, thus a wrapper is required */
        get_challenge:         Some(acos5_get_challenge),     // iso7816_get_challenge
        /* verify:                NULL, deprecated */
        logout:                Some(acos5_logout),            // NULL
        /* restore_security_env                                  // iso7816_restore_security_env */
        set_security_env:      Some(acos5_set_security_env),  // iso7816_set_security_env
            /* iso7816_set_security_env doesn't work for signing; do set CRT B6 and B8 */
        decipher:              Some(acos5_decipher),          // iso7816_decipher,  not suitable for cos5
        compute_signature:     Some(acos5_compute_signature), // iso7816_compute_signature,  not suitable for cos5
        /* change_reference_data: NULL, deprecated */
        /* reset_retry_counter:   NULL, deprecated */
            /* create_file: iso7816_create_file  is usable, provided that construct_fci is suitable */
        create_file:           Some(acos5_create_file),       // iso7816_create_file
            /* delete_file: iso7816_delete_file  is usable, BUT pay ATTENTION, how path.len selects among alternatives;
                        AND, even with path, it must first be selected */
        delete_file:           Some(acos5_delete_file),       // iso7816_delete_file
        list_files:            Some(acos5_list_files),        // NULL
        /* check_sw:                                         // iso7816_check_sw
            iso7816_check_sw basically is usable except that for pin_cmd cmd=SC_PIN_CMD_GET_INFO, the correct answer like
            0x63C8 (8 tries left) is interpreted as a failing pin verification trial (SC_ERROR_PIN_CODE_INCORRECT)
            thus trying to go with iso7816_check_sw, reroute that pin_cmd cmd=SC_PIN_CMD_GET_INFO to not employ check_sw
           TODO  iso7816_check_sw has an internal table to map return status to text: this doesn't match the ACOS5 mapping in some cases, THUS maybe switching on/off check_sw==iso7816_check_sw may be required
        */
        card_ctl:              Some(acos5_card_ctl),          // NULL
        process_fci:           Some(acos5_process_fci),       // iso7816_process_fci is insufficient for cos5: It will be used, but more has to be done for cos5
        construct_fci:         Some(acos5_construct_fci),     // iso7816_construct_fci
        pin_cmd:               Some(acos5_pin_cmd),           // iso7816_pin_cmd
            /* pin_cmd:
            SC_PIN_CMD_GET_INFO: iso7816_pin_cmd not suitable for SC_PIN_CMD_GET_INFO (only because the status word is
                                   mis-interpreted by iso7816_check_sw as failed pin verification)
            SC_PIN_CMD_VERIFY:   iso7816_pin_cmd is okay for  SC_PIN_CMD_VERIFY
            SC_PIN_CMD_CHANGE:   iso7816_pin_cmd is okay for  SC_PIN_CMD_CHANGE
            SC_PIN_CMD_UNBLOCK:  iso7816_pin_cmd is okay for  SC_PIN_CMD_UNBLOCK
            */
        /* get_dat:                                              iso7816_get_data */
        /* put_data:                                             NULL, put a data object  write to Data Object */
        read_public_key:       Some(acos5_read_public_key),   // NULL
        /* card_reader_lock_obtained:                            NULL */
        /* wrap:                                                 NULL */
        #[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
        unwrap:                Some(acos5_unwrap),            // NULL

        ..iso_ops // untested so far whether remaining functionality from libopensc/iso7816.c is sufficient for cos5
/* from iso_ops:
    NULL,            /* verify,                deprecated */

>>  iso7816_restore_security_env,
    NULL,            /* change_reference_data, deprecated */
    NULL,            /* reset_retry_counter,   deprecated */

>>  iso7816_check_sw,

>>  iso7816_get_data,
    NULL,            /* put_data */

    NULL,            /* card_reader_lock_obtained */
    NULL,            /* wrap */
*/
    } );

    let b_sc_card_driver = Box::new( sc_card_driver {
        name:       CStr::from_bytes_with_nul(CARD_DRV_NAME).unwrap().as_ptr(),
        short_name: CStr::from_bytes_with_nul(CARD_DRV_SHORT_NAME).unwrap().as_ptr(),
        ops:        Box::into_raw(b_sc_card_operations),
        ..sc_card_driver::default()
    } );
    Box::into_raw(b_sc_card_driver)
}


/*
match_card as other cards do,
(based on ATR from driver and/or opensc.conf? )
additionally optional:
exclude non-64K, i.e. exclude
V2: 32K mode

V3: 32K mode
V3: FIPS mode
V3: Brasil mode

additionally optional:
check cos version

additionally optional:
check operation Mode Byte Setting for V3

TODO how to set opensc.conf, such that a minimum of trials to match atr is done
*/
/**
 *  @param  card  sc_card object (treated as *const sc_card)
 *  @return 1 on succcess i.e. card did match, otherwise 0
 */
/*
 * Implements sc_card_operations function 'match_card'
 * @see opensc_sys::opensc pub struct sc_card_operations
 * @apiNote
 * @param
 * @return 1 on success (this driver will serve the card), 0 otherwise
 */
extern "C" fn acos5_match_card(card_ptr: *mut sc_card) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } {
        return 0;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun  = CStr::from_bytes_with_nul(b"acos5_match_card\0").unwrap();
    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(),fun,unsafe{sc_dump_hex(card.atr.value.as_ptr(), card.atr.len)},
            CStr::from_bytes_with_nul(b"called. Try to match card with ATR %s\0").unwrap() );
    }

    #[cfg(    any(v0_17_0, v0_18_0))]
    let mut acos5_atrs = acos5_supported_atrs();
    #[cfg(not(any(v0_17_0, v0_18_0)))]
    let     acos5_atrs = acos5_supported_atrs();
    /* check whether card.atr can be found in acos5_supported_atrs[i].atr, iff yes, then
       card.type_ will be set accordingly, but not before the successful return of match_card */
    let mut type_out = 0;
    #[cfg(    any(v0_17_0, v0_18_0))]
    let idx_acos5_atrs = unsafe { _sc_match_atr(card, (&mut acos5_atrs).as_mut_ptr(), &mut type_out) };
    #[cfg(not(any(v0_17_0, v0_18_0)))]
    let idx_acos5_atrs = unsafe { _sc_match_atr(card, (   & acos5_atrs).as_ptr(),     &mut type_out) };
////println!("idx_acos5_atrs: {}, card.type_: {}, type_out: {}, &card.atr.value[..19]: {:?}\n", idx_acos5_atrs, card.type_, type_out, &card.atr.value[..19]);

    card.type_ = 0;

    if idx_acos5_atrs < 0 || idx_acos5_atrs+2 > acos5_atrs.len() as i32 {
        if cfg!(log) {
            wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(
                b"Card doesn't match: Differing ATR\0").unwrap());
        }
        return 0;
    }
    let idx_acos5_atrs = idx_acos5_atrs as usize;

    /* check for 'Identity Self' */
    match get_ident_self(card) {
        Ok(val) => if !val { return 0; },
        Err(_e) => { return 0; },
    };

    /* * / //optional checks
    /* check for 'Card OS Version' */
    let rbuf_card_os_version = match get_cos_version(card) {
        Ok(val) => val,
        Err(e) => return e,
    };

    //    println!("rbuf_card_os_version: {:?}", &rbuf_card_os_version[..]);
    // rbuf_card_os_version: [0x41, 0x43, 0x4F, 0x53, 0x05, 0x02, 0x00, 0x40] from Cryptomate64  b"ACOS___@"
    // rbuf_card_os_version: [0x41, 0x43, 0x4F, 0x53, 0x05, 0x03, 0x01, 0x40] from CryptoMate Nano in op mode 64 K
    // rbuf_card_os_version: [0x41, 0x43, 0x4F, 0x53, 0x05, 0x03, 0x00, 0x40] from CryptoMate Nano in op mode FIPS
        if rbuf_card_os_version[..5] != [0x41u8, 0x43, 0x4F, 0x53, 0x05] || rbuf_card_os_version[7] !=  0x40
        {
            if cfg!(log) {
                let fmt = CStr::from_bytes_with_nul(b"Card doesn't match: sc_transmit_apdu or ACOS5-64 'Card OS Version'\
                    -check failed\0").unwrap();
                wr_do_log(card_ctx, f_log, line!(), fun, fmt);
            }
            return 0;
        }
        match type_out {
            /* rbuf_card_os_version[5] is the major version */
            /* rbuf_card_os_version[6] is the minor version
               probably minor version reflects the  'Operation Mode Byte Setting',
               thus relax req. for SC_CARD_TYPE_ACOS5_64_V3, iff FIPS mode should ever be supported */
            SC_CARD_TYPE_ACOS5_64_V2  =>  { if rbuf_card_os_version[5] != 2    ||  rbuf_card_os_version[6] != 0    { return 0; } },
            SC_CARD_TYPE_ACOS5_64_V3  =>  { if rbuf_card_os_version[5] != 3 /* ||  rbuf_card_os_version[6] != 1 */ { return 0; } },
             _                             =>  { return 0; },
        }

        /* excludes any mode except 64K (no FIPS, no 32K, no brasil) */
        if type_out == SC_CARD_TYPE_ACOS5_64_V3 {

            /* check 'Operation Mode Byte Setting', must be set to  */
            let op_mode_byte = match get_op_mode_byte(card) {
                Ok(op_mb) => op_mb,
                Err(_err) =>  0x7FFF_FFFFu32,
            };

            if op_mode_byte != 2 {
                if cfg!(log) {
                    let fmt = CStr::from_bytes_with_nul(b"ACOS5-64 v3.00 'Operation mode==Non-FIPS (64K)'-check failed. Trying to change the mode of operation to Non-FIPS/64K mode (no other mode is supported currently)....\0").unwrap();
                    wr_do_log(card_ctx, f_log, line!(), fun, fmt);
                }
                // FIXME try to change the operation mode byte if there is no MF
                let mf_path_ref: &sc_path = unsafe { &*sc_get_mf_path() };
                let mut file : *mut sc_file = null_mut();
                let mut rv = unsafe { sc_select_file(card, mf_path_ref, &mut file) };
                println!("rv from sc_select_file: {}, file: {:?}", rv, file); // rv from sc_select_file: -1200, file: 0x0
                let fmt = CStr::from_bytes_with_nul(b"Card doesn't match: sc_transmit_apdu or 'change to operation mode 64K' failed ! Have a look into docs how to change the mode of operation to Non-FIPS/64K mode. No other mode is supported currently\0").unwrap();
                if rv == SC_SUCCESS {
                    if cfg!(log) {
                        wr_do_log(card_ctx, f_log, line!(), fun, fmt);
                    }
                    return 0;
                }
                // if sc_select_file failed, try to write value 2 to address 0xC191
                let command = [0, 0xD6, 0xC1, 0x91, 0x01, 0x02];
                let mut apdu = sc_apdu::default();
                rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
                assert_eq!(rv, SC_SUCCESS);
                assert_eq!(apdu.cse, SC_APDU_CASE_3_SHORT);
                rv = unsafe { sc_transmit_apdu(card, &mut apdu) };
                if rv != SC_SUCCESS || apdu.sw1 != 0x90 || apdu.sw2 != 0x00 {
                    if cfg!(log) {
                        wr_do_log(card_ctx, f_log, line!(), fun, fmt);
                    }
                    return 0;
                }
                else {
                    let fmt = CStr::from_bytes_with_nul(b"Card was set to Operation Mode 64K (SUCCESS) !\0").unwrap();
                    if cfg!(log) {
                        wr_do_log(card_ctx, f_log, line!(), fun, fmt);
                    }
                }
            }
        }
    / **/

    // Only now, on success, set card.type
    card.type_ = type_out;
    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(), fun, acos5_atrs[idx_acos5_atrs].name,
                    CStr::from_bytes_with_nul(b"'%s' card matched\0").unwrap());
    }
    1
}


/*
what can we rely on, when this get's called:
1. card.atr  was set
2. card.type was set by match_card, but it may still be incorrect, as a forced_card driver ignores
     a no-match on ATR and nevertheless calls init, thus rule out non-matching ATR card finally here
*/
/**
 *  @param  card  struct sc_card object
 *  @return SC_SUCCESS or error code from errors.rs
 */
/*
 * What it does
 * @apiNote
 * @param
 * @return
 */
extern "C" fn acos5_init(card_ptr: *mut sc_card) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun  = CStr::from_bytes_with_nul(b"acos5_init\0").unwrap();
    if cfg!(log) {
        wr_do_log_tu(card_ctx, f_log, line!(), fun, card.type_, unsafe {sc_dump_hex(card.atr.value.as_ptr(),
          card.atr.len) }, CStr::from_bytes_with_nul(b"called with card.type: %d, card.atr.value: %s\0").unwrap());
    }
    if !card_ctx.app_name.is_null() {
        let app_name = unsafe { CStr::from_ptr(card_ctx.app_name) }; // app_name: e.g. "pkcs15-init"
        if cfg!(log) {
            wr_do_log_t(card_ctx, f_log, line!(), fun, app_name.as_ptr(),
                        CStr::from_bytes_with_nul(b"The driver was loaded for application: %s\0").unwrap());
        }
//        println!("{}", String::from("The driver was loaded for application: ") + app_name.to_str().unwrap());
    }

    /* Undo 'force_card_driver = acos5_external;'  if match_card reports 'no match' */
    for elem in &acos5_supported_atrs() {
        if elem.atr.is_null() {
            if cfg!(log) {
                wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(b"### Error, have to skip \
                    driver 'acos5_external'! Got here, though match_card reported 'no match' (probably by using \
                    'force_card_driver = acos5_external;') ###\0").unwrap());
            }
            return SC_ERROR_WRONG_CARD;
        }
        if elem.type_ == card.type_ {
            card.name = elem.name;
            card.flags = elem.flags; // FIXME maybe omit her and set later
            break;
        }
    }

    unsafe{sc_format_path(CStr::from_bytes_with_nul(b"3F00\0").unwrap().as_ptr(), &mut card.cache.current_path);} // type = SC_PATH_TYPE_PATH;
    card.cla  = 0x00;                                        // int      default APDU class (interindustry)
    /* max_send_size  IS  treated as a constant (won't change) */
    card.max_send_size = SC_READER_SHORT_APDU_MAX_SEND_SIZE; // 0x0FF; // 0x0FFFF for usb-reader, 0x0FF for chip/card;  Max Lc supported by the card
    /* max_recv_size  IS NOT  treated as a constant (it will be set temporarily to SC_READER_SHORT_APDU_MAX_RECV_SIZE where commands do support interpreting le byte 0 as 256 (le is 1 byte only!), like e.g. acos5_compute_signature) */
    /* some commands return 0x6100, meaning, there are 256==SC_READER_SHORT_APDU_MAX_RECV_SIZE  bytes (or more) to fetch */
    card.max_recv_size = SC_READER_SHORT_APDU_MAX_SEND_SIZE; //reduced as long as iso7816_read_binary is used: 0==0x100 is not understood // 0x100; // 0x10000 for usb-reader, 0x100 for chip/card;  Max Le supported by the card, decipher (in chaining mode) with a 4096-bit key returns 2 chunks of 256 bytes each !!

    /* possibly more SC_CARD_CAP_* apply, TODO clarify */
    card.caps    = SC_CARD_CAP_RNG | SC_CARD_CAP_USE_FCI_AC | SC_CARD_CAP_ISO7816_PIN_INFO;
    /* card.caps |= SC_CARD_CAP_PROTECTED_AUTHENTICATION_PATH   what exactly is this? */
    #[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
    { card.caps |=  /*SC_CARD_CAP_WRAP_KEY | */ SC_CARD_CAP_UNWRAP_KEY; }
    /* The reader of USB CryptoMate64/CryptoMate Nano supports extended APDU, but the ACOS5-64 cards don't: Thus SC_CARD_CAP_APDU_EXT only for ACOS5-EVO TODO */

    /* it's possible to add SC_ALGORITHM_RSA_RAW, but then pkcs11-tool -t needs insecure cfg=dev_relax_signature_constraints_for_raw */
    let rsa_algo_flags = SC_ALGORITHM_ONBOARD_KEY_GEN | SC_ALGORITHM_RSA_PAD_PKCS1 /* | SC_ALGORITHM_RSA_RAW*/;
//    rsa_algo_flags   |= SC_ALGORITHM_RSA_RAW; // PSS works with that only currently via acos5_decipher; declaring SC_ALGORITHM_RSA_PAD_PSS seems superfluous
//    rsa_algo_flags   |= SC_ALGORITHM_RSA_PAD_PKCS1;
//    #[cfg(not(any(v0_17_0, v0_18_0)))]
//    { rsa_algo_flags |= SC_ALGORITHM_RSA_PAD_PSS; }
//    rsa_algo_flags   |= SC_ALGORITHM_RSA_PAD_ISO9796; // cos5 supports ISO9796, but don't use this, see https://www.iacr.org/archive/eurocrypt2000/1807/18070070-new.pdf
//    rsa_algo_flags   |= SC_ALGORITHM_RSA_PAD_NONE; // for cfg!(any(v0_17_0, v0_18_0, v0_19_0)) this is a NOOP, as SC_ALGORITHM_RSA_PAD_NONE is zero then

    /* SC_ALGORITHM_NEED_USAGE : Don't use that: the driver will handle that for sign internally ! */
    /* Though there is now some more hash related info in opensc.h, still it's not clear to me whether to apply any of
         SC_ALGORITHM_RSA_HASH_NONE or SC_ALGORITHM_RSA_HASH_SHA256 etc. */
//    rsa_algo_flags |= SC_ALGORITHM_RSA_HASH_NONE;
//    rsa_algo_flags |= SC_ALGORITHM_RSA_HASH_SHA256;
//    rsa_algo_flags |= SC_ALGORITHM_MGF1_SHA256;

    let is_fips_compliant = card.type_ > SC_CARD_TYPE_ACOS5_64_V2 &&
        get_op_mode_byte(card).unwrap()==0 && get_fips_compliance(card).unwrap();
    let mut rv;
    let     rsa_key_len_from : u32 = if is_fips_compliant { 2048 } else {  512 };
    let     rsa_key_len_step : u32 = if is_fips_compliant { 1024 } else {  256 };
    let     rsa_key_len_to   : u32 = if is_fips_compliant { 3072 } else { 4096 };
    let mut rsa_key_len = rsa_key_len_from;
    while   rsa_key_len <= rsa_key_len_to {
        rv = unsafe { _sc_card_add_rsa_alg(card, rsa_key_len, rsa_algo_flags as c_ulong, 0/*0x10001*/) };
        if rv != SC_SUCCESS {
            return rv;
        }
        rsa_key_len += rsa_key_len_step;
    }

    if card.type_ == SC_CARD_TYPE_ACOS5_EVO_V4 {
        let flags = SC_ALGORITHM_ONBOARD_KEY_GEN | SC_ALGORITHM_ECDSA_RAW; /*| SC_ALGORITHM_ECDH_CDH_RAW |
                           SC_ALGORITHM_ECDSA_HASH_NONE | SC_ALGORITHM_ECDSA_HASH_SHA1*/
        let ext_flags = SC_ALGORITHM_EXT_EC_NAMEDCURVE; /*| SC_ALGORITHM_EXT_EC_UNCOMPRESES*/
        for elem in &mut acos5_supported_ec_curves() {
            unsafe { _sc_card_add_ec_alg(card, elem.size, flags as c_ulong, ext_flags as c_ulong, &mut elem.curve_oid) };
        }
    }

    /* ACOS5 is capable of DES, but I think we can just skip that insecure algo; and the next, 3DES/128 with key1==key3 should NOT be used */
    me_card_add_symmetric_alg(card, SC_ALGORITHM_DES,  64,  0);
//    me_card_add_symmetric_alg(card, SC_ALGORITHM_3DES, 128, 0);
    me_card_add_symmetric_alg(card, SC_ALGORITHM_3DES, 192, 0);

    let aes_algo_flags;
    #[cfg(    any(v0_17_0, v0_18_0, v0_19_0))]
    { aes_algo_flags = 0; }
    #[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
    { aes_algo_flags = SC_ALGORITHM_AES_FLAGS; }
    me_card_add_symmetric_alg(card, SC_ALGORITHM_AES, 128, aes_algo_flags);
    me_card_add_symmetric_alg(card, SC_ALGORITHM_AES, 192, aes_algo_flags);
    me_card_add_symmetric_alg(card, SC_ALGORITHM_AES, 256, aes_algo_flags);
    assert!( me_card_find_alg(card, SC_ALGORITHM_AES, 256, None).is_some());
////////////////////////////////////////
    /* stores serialnr in card.serialnr, required for enum_dir */
    match get_serialnr(card) {
        Ok(_val) => (),
        Err(e) => return e,
    };
////////////////////////////////////////
    let mut files : HashMap<KeyTypeFiles, ValueTypeFiles> = HashMap::with_capacity(50);
    files.insert(0x3F00, (
        [0; SC_MAX_PATH_SIZE],
        [0x3F, 0xFF, 0x3F, 0x00, 0x00, 0x00, 0xFF, 0xFF], // File Info, 0xFF are incorrect byte settings, corrected later
        None, //Some([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]), // scb8, ditto. concerning 0xFF
        None, // Some(vec_SACinfo),
        None, // Some(vec_SAEinfo),
    ));

    let dp = Box::new( DataPrivate {
        files,
        sec_env: sc_security_env::default(),
        agc: CardCtl_generate_crypt_asym::default(),
        agi: CardCtl_generate_inject_asym::default(),
        time_stamp: std::time::Instant::now(),
        sec_env_mod_len: 0,
        rfu_align_pad1: 0,
        rsa_caps: rsa_algo_flags,
        does_mf_exist: true,       // just an assumption; will be set in enum_dir
        is_fips_mode: false,       // just an assumption; will be set in
        is_fips_compliant : false, // just an assumption; will be set in
        is_running_init: true,
        is_running_compute_signature: false,
        is_running_cmd_long_response: false,
        is_unwrap_op_in_progress: false,
        rfu_align_pad2 : false,
        sym_key_file_id: 0,
        sym_key_rec_idx: 0,
        sym_key_rec_cnt: 0,
        #[cfg(enable_acos5_ui)]
        ui_ctx: ui_context::default(),
    } );

/*
println!("address of dp:         {:p}",  dp);
println!("address of dp.files:   {:p}", &dp.files);
println!("address of dp.sec_env: {:p}", &dp.sec_env);
address of dp:         0x5580a78edbb0
address of dp.files:   0x5580a78edbb0
address of dp.sec_env: 0x5580a78edbe8
*/

    card.drv_data = Box::into_raw(dp) as *mut c_void;

/*
println!("offset_of files:                            {}, Δnext:   {}, size_of:   {}, align_of: {}", offset_of!(DataPrivate, files),   offset_of!(DataPrivate, sec_env)-offset_of!(DataPrivate, files), std::mem::size_of::<HashMap<KeyTypeFiles,ValueTypeFiles>>(), std::mem::align_of::<HashMap<KeyTypeFiles,ValueTypeFiles>>());
println!("offset_of sec_env:                         {}, Δnext: {}, size_of: {}, align_of: {}", offset_of!(DataPrivate, sec_env),      offset_of!(DataPrivate, agc)-offset_of!(DataPrivate, sec_env), std::mem::size_of::<sc_security_env>(), std::mem::align_of::<sc_security_env>());
println!("offset_of agc:                           {}, Δnext:  {}, size_of:  {}, align_of: {}", offset_of!(DataPrivate, agc),          offset_of!(DataPrivate, agi)-offset_of!(DataPrivate, agc), std::mem::size_of::<CardCtl_generate_crypt_asym>(), std::mem::align_of::<CardCtl_generate_crypt_asym>());
println!("offset_of agi:                           {}, Δnext:   {}, size_of:   {}, align_of: {}", offset_of!(DataPrivate, agi),        offset_of!(DataPrivate, time_stamp)-offset_of!(DataPrivate, agi), std::mem::size_of::<CardCtl_generate_inject_asym>(), std::mem::align_of::<CardCtl_generate_inject_asym>());
println!("offset_of time_stamp:                    {}, Δnext:   {}, size_of:   {}, align_of: {}", offset_of!(DataPrivate, time_stamp), offset_of!(DataPrivate, sec_env_mod_len)-offset_of!(DataPrivate, time_stamp), std::mem::size_of::<std::time::Instant>(), std::mem::align_of::<std::time::Instant>());

println!("offset_of sec_env_mod_len:               {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, sec_env_mod_len), offset_of!(DataPrivate, rfu_align_pad1)-offset_of!(DataPrivate, sec_env_mod_len), std::mem::size_of::<c_ushort>(), std::mem::align_of::<c_ushort>());
println!("offset_of rfu_align_pad1:                {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, rfu_align_pad1),  offset_of!(DataPrivate, rsa_caps)-offset_of!(DataPrivate, rfu_align_pad1), std::mem::size_of::<c_ushort>(), std::mem::align_of::<c_ushort>());

println!("offset_of rsa_caps:                      {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, rsa_caps),        offset_of!(DataPrivate, does_mf_exist)-offset_of!(DataPrivate, rsa_caps), std::mem::size_of::<c_uint>(), std::mem::align_of::<c_uint>());
println!("offset_of does_mf_exist:                 {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, does_mf_exist),   offset_of!(DataPrivate, is_fips_mode)-offset_of!(DataPrivate, does_mf_exist), std::mem::size_of::<bool>(), std::mem::align_of::<bool>());
println!("offset_of is_fips_mode:                  {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, is_fips_mode),    offset_of!(DataPrivate, is_fips_compliant)-offset_of!(DataPrivate, is_fips_mode), std::mem::size_of::<bool>(), std::mem::align_of::<bool>());

println!("offset_of is_fips_compliant:             {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, is_fips_compliant),            offset_of!(DataPrivate, is_running_init)-offset_of!(DataPrivate, is_fips_compliant), std::mem::size_of::<bool>(), std::mem::align_of::<bool>());
println!("offset_of is_running_init:               {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, is_running_init),              offset_of!(DataPrivate, is_running_compute_signature)-offset_of!(DataPrivate, is_running_init), std::mem::size_of::<bool>(), std::mem::align_of::<bool>());
println!("offset_of is_running_compute_signature:  {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, is_running_compute_signature), offset_of!(DataPrivate, is_running_cmd_long_response)-offset_of!(DataPrivate, is_running_compute_signature), std::mem::size_of::<bool>(), std::mem::align_of::<bool>());
println!("offset_of is_running_cmd_long_response:  {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, is_running_cmd_long_response), offset_of!(DataPrivate, is_unwrap_op_in_progress)-offset_of!(DataPrivate, is_running_cmd_long_response), std::mem::size_of::<bool>(), std::mem::align_of::<bool>());
println!("offset_of is_unwrap_op_in_progress:      {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, is_unwrap_op_in_progress),     offset_of!(DataPrivate, rfu_align_pad2)-offset_of!(DataPrivate, is_unwrap_op_in_progress), std::mem::size_of::<bool>(), std::mem::align_of::<bool>());
println!("offset_of rfu_align_pad2:                {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, rfu_align_pad2),               offset_of!(DataPrivate, sym_key_file_id)-offset_of!(DataPrivate, rfu_align_pad2), std::mem::size_of::<bool>(), std::mem::align_of::<bool>());

println!("offset_of sym_key_file_id:               {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, sym_key_file_id), offset_of!(DataPrivate, sym_key_rec_idx)-offset_of!(DataPrivate, sym_key_file_id), std::mem::size_of::<u16>(), std::mem::align_of::<u16>());
println!("offset_of sym_key_rec_idx:               {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, sym_key_rec_idx), offset_of!(DataPrivate, sym_key_rec_cnt)-offset_of!(DataPrivate, sym_key_rec_idx), std::mem::size_of::<u8>(), std::mem::align_of::<u8>());
println!("offset_of sym_key_rec_cnt:               {}, Δnext:    {}, size_of:    {}, align_of: {}", offset_of!(DataPrivate, sym_key_rec_cnt), std::mem::size_of::<DataPrivate>()-offset_of!(DataPrivate, sym_key_rec_cnt), std::mem::size_of::<u8>(), std::mem::align_of::<u8>());

println!("DataPrivate:                                                size_of: {}, align_of: {}", std::mem::size_of::<DataPrivate>(), std::mem::align_of::<DataPrivate>()); // DataPrivate: size_of: 1784, align_of: 8


offset_of files:                            0, Δnext:   56, size_of:   56, align_of: 8
offset_of sec_env:                         56, Δnext: 1112, size_of: 1112, align_of: 8
offset_of agc:                           1168, Δnext:  552, size_of:  552, align_of: 8
offset_of agi:                           1720, Δnext:   24, size_of:   24, align_of: 2
offset_of time_stamp:                    1744, Δnext:   16, size_of:   16, align_of: 8
offset_of sec_env_mod_len:               1760, Δnext:    2, size_of:    2, align_of: 2
offset_of rfu_align_pad1:                1762, Δnext:    2, size_of:    2, align_of: 2
offset_of rsa_caps:                      1764, Δnext:    4, size_of:    4, align_of: 4
offset_of does_mf_exist:                 1768, Δnext:    1, size_of:    1, align_of: 1
offset_of is_fips_mode:                  1769, Δnext:    1, size_of:    1, align_of: 1
offset_of is_fips_compliant:             1770, Δnext:    1, size_of:    1, align_of: 1
offset_of is_running_init:               1771, Δnext:    1, size_of:    1, align_of: 1
offset_of is_running_compute_signature:  1772, Δnext:    1, size_of:    1, align_of: 1
offset_of is_running_cmd_long_response:  1773, Δnext:    1, size_of:    1, align_of: 1
offset_of is_unwrap_op_in_progress:      1774, Δnext:    1, size_of:    1, align_of: 1
offset_of rfu_align_pad2:                1775, Δnext:    1, size_of:    1, align_of: 1
offset_of sym_key_file_id:               1776, Δnext:    2, size_of:    2, align_of: 2
offset_of sym_key_rec_idx:               1778, Δnext:    1, size_of:    1, align_of: 1
offset_of sym_key_rec_cnt:               1779, Δnext:    5, size_of:    1, align_of: 1
DataPrivate:                                                size_of: 1784, align_of: 8
*/

    let mut path_mf = sc_path::default();
    unsafe { sc_format_path(CStr::from_bytes_with_nul(b"3F00\0").unwrap().as_ptr(), &mut path_mf); } // type = SC_PATH_TYPE_PATH;
    rv = enum_dir(card, &path_mf, true/*, 0*/); /* FIXME Doing to much here degrades performance, possibly for no value */
    assert_eq!(rv, SC_SUCCESS);
    unsafe { sc_select_file(card, &path_mf, null_mut()) };

    let sm_info = &mut card.sm_ctx.info;
//  char[64]  config_section;  will be set from opensc.conf later by sc_card_sm_check
//  uint      sm_mode;         will be set from opensc.conf later by sc_card_sm_check only for SM_MODE_TRANSMIT
    sm_info.serialnr  = card.serialnr;
//    unsafe { copy_nonoverlapping(CStr::from_bytes_with_nul(b"acos5_sm\0").unwrap().as_ptr(), sm_info.config_section.as_mut_ptr(), 9); } // used to look-up the block; only iasecc/authentic populate this field
    sm_info.card_type = card.type_ as c_uint;
    sm_info.sm_type   = SM_TYPE_CWA14890;
    unsafe { sm_info.session.cwa.params.crt_at.refs[0] = 0x82 }; // this is the selection of keyset_... ...02_... to be used !!! Currently 24 byte keys (generate 24 byte session keys)
//       assert(0);//session.cwa.params.crt_at.refs[0] = 0x81;   // this is the selection of keyset_... ...01_... to be used !!!           16 byte keys (generate 16 byte session keys)
//        if (card.cache.current_df)
//        current_path_df                 = card.cache.current_df.path;
    sm_info.current_aid = sc_aid { len: SC_MAX_AID_SIZE, value: [0x41, 0x43, 0x4F, 0x53, 0x50, 0x4B, 0x43, 0x53, 0x2D, 0x31, 0x35, 0x76, 0x31, 0x2E, 0x30, 0x30]}; //"ACOSPKCS-15v1.00", see PKCS#15 EF.DIR file
//  card.sm_ctx.module.ops  : handled by card.c:sc_card_sm_check/sc_card_sm_load

    let mut dp= unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
    dp.files.shrink_to_fit();
    dp.is_running_init = false;

    #[cfg(enable_acos5_ui)]
    {
        /* read environment from configuration file */
//println!("dp.ui_ctx.user_consent_enabled: {}", dp.ui_ctx.user_consent_enabled);
        rv = set_ui_ctx(card, &mut dp.ui_ctx);
//println!("dp.ui_ctx.user_consent_enabled: {}", dp.ui_ctx.user_consent_enabled);
        if rv < SC_SUCCESS {
            unsafe { wr_do_log_sds(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(b"set_ui_ctx failed.\0").unwrap().as_ptr(),
                          rv, sc_strerror(rv), CStr::from_bytes_with_nul(b"%s: %d (%s)\n\0").unwrap() )};
        }
    }
    card.drv_data = Box::into_raw(dp) as *mut c_void;

    if cfg!(log) {
        wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) },
                     CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
    }
    rv
} // acos5_init


/*
 * What it does
 * @apiNote
 * @param
 * @return
 */
extern "C" fn acos5_finish(card_ptr: *mut sc_card) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun = CStr::from_bytes_with_nul(b"acos5_finish\0").unwrap();
    if cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(CALLED).unwrap());
    }
////////////////////
/*
    let mut path_x = sc_path::default();
    unsafe { sc_format_path(CStr::from_bytes_with_nul(b"i3F00\0").unwrap().as_ptr(), &mut path_x); }
    let mut rv = unsafe { sc_select_file(card, &path_x, null_mut()) };
    assert_eq!(SC_SUCCESS, rv);

    path_x = sc_path::default();
//    let mut file_x = null_mut::<sc_file>();
    let df_name = [b'd', b'i', b'r', b'e', b'c', b't', b'o', b'r', b'y', b'1'];
    rv = unsafe { sc_path_set(&mut path_x, SC_PATH_TYPE_DF_NAME, df_name.as_ptr(), df_name.len(), 0, -1) };
    assert_eq!(SC_SUCCESS, rv);
    rv = unsafe { sc_select_file(card, &path_x, null_mut()) };
    assert_eq!(SC_SUCCESS, rv);
//    unsafe { sc_file_free(file_x) };
*/
/* some testing
    if false && card.type_ > SC_CARD_TYPE_ACOS5_64_V2 {
        let mut path = sc_path::default();
        /* this file requires pin verification for sc_update_binary and the DF requires SM for pin verification */
        unsafe { sc_format_path(CStr::from_bytes_with_nul(b"3F00410045004504\0").unwrap().as_ptr(), &mut path) };
//println!("path.len: {}, path.value: {:X?}", path.len, path.value);
        let mut rv = acos5_select_file(card, &path, null_mut());
        assert_eq!(rv, SC_SUCCESS);

        let mut tries_left = 0;
        let pin_user: [u8; 8] = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38]; // User pin, local  12345678
        let mut pin_cmd_data = sc_pin_cmd_data {
            cmd: SC_PIN_CMD_VERIFY, // SC_PIN_CMD_GET_INFO  SC_PIN_CMD_VERIFY
            pin_reference: 0x81,
            pin1: sc_pin_cmd_pin {
                data: pin_user.as_ptr(),
                len:  pin_user.len() as c_int,
                ..sc_pin_cmd_pin::default()
            },
            ..sc_pin_cmd_data::default()
        };
        rv = unsafe { sc_pin_cmd(card, &mut pin_cmd_data, &mut tries_left) };
println!("Pin verification performed for DF {:X}, resulting in pin_user_verified/get_info: {}, rv: {}, tries_left: {}", 0x4500, rv == SC_SUCCESS, rv, tries_left);

        let sbuf = [0x01, 0x02];
        rv = unsafe { sc_update_binary(card, 0, sbuf.as_ptr(), sbuf.len(), 0) };
println!("sc_update_binary: rv: {}", rv);
    }
*/
    /*
    00a40000024100
    00c0000032
    00a40000024500
    00c0000028
    00a40000024503
    00c0000020
    00b201040b
    00b2020415
    00b203041f
    00a40000024504
    00c0000020
    00200081083132333435363738
    00d60000020102
    */
////////////////////
    assert!(!card.drv_data.is_null(), "drv_data is null");
    let dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
//println!("Hashmap: {:X?}", dp.files);
//    there may be other Boxes that might need to be taken over again
    drop(dp);
    card.drv_data = null_mut();
    SC_SUCCESS
}


/**
  Erases bytes (i.e. sets bytes to value 0x00) in a transparent file, within a chosen range of file's size
  The underlying card command does that beginning from a start_offset until either end_offset or end of file
  This OpenSC function has the parameter idx for start_offset, and a parameter 'count' for how many bytes shall be cleared to zero.
  Use the special value count=0xFFFF (a value far beyond possible file sizes) in order to denote clearing bytes until the end of the file
  TODO check what happens if end_offset > file's size

@param count indicates the number of bytes to erase
@return SC_SUCCESS or other SC_..., NO length !
 * @return number of bytes written or an error code
@requires prior file selection
*/
extern "C" fn acos5_erase_binary(card_ptr: *mut sc_card, idx: c_uint, count: usize, flags: c_ulong) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let idx = idx as u16;
    let count = count as u16;
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun   = CStr::from_bytes_with_nul(b"acos5_erase_binary\0").unwrap();
    if cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(CALLED).unwrap());
    }

    let file_id = file_id_from_cache_current_path(card);
    let dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
    let dp_files_value = &dp.files[&file_id];
    let fdb = dp_files_value.1[0];
    let size = u16::from_be_bytes([dp_files_value.1[4], dp_files_value.1[5]]);
    let scb_erase = dp_files_value.2.unwrap()[1];
    card.drv_data = Box::into_raw(dp) as *mut c_void;
////println!("idx: {}, count: {}, flags: {}, fdb: {}, size: {}, scb_erase: {}", idx, count, flags, fdb, size, scb_erase);
    if ![1, 9].contains(&fdb) {
        return SC_ERROR_INVALID_ARGUMENTS;
    }

    if scb_erase == 0xFF {
        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(
            b"No erase_binary will be done: The file has acl NEVER ERASE\0").unwrap());
        SC_ERROR_SECURITY_STATUS_NOT_SATISFIED
    }
    else if (scb_erase & 0x40) == 0x40 {
        let res_se_sm = se_get_is_scb_suitable_for_sm_has_ct(card, file_id, scb_erase & 0x0F);
        if !res_se_sm.0 {
            wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(
                b"No erase_binary will be done: The file has acl SM-protected ERASE\0").unwrap());
            SC_ERROR_SECURITY_STATUS_NOT_SATISFIED
        }
        else {
            // forward to SM processing, no P3==0
            let mut count = count;
            if idx + count > size {
               if idx >= size || count == 0 { return SC_SUCCESS; }
               count = size - idx;
            }
            sm_erase_binary(card, idx, count, flags, res_se_sm.1)
        }
    }
    else {
        let command = [0_u8, 0x0E, 0, 0,  2, 0xFF, 0xFF];
        let mut apdu = sc_apdu::default();
        let mut rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
        assert_eq!(rv, SC_SUCCESS);
        assert_eq!(apdu.cse, SC_APDU_CASE_3_SHORT);
        apdu.flags = flags;

        if idx != 0 {
            let arr2 : [u8; 2] = idx.to_be_bytes();
            apdu.p1 = arr2[0]; // start_offset (included)
            apdu.p2 = arr2[1]; // dito
        }
        let mut end_offset = [0x00, 0x00];
        let mut count = count;
        if idx + count >= size { // TODO what if idx (+count) >= size ?
            if idx >= size || count == 0 { return SC_SUCCESS; }
            count = size - idx;

            apdu.cse = SC_APDU_CASE_1;
            apdu.lc = 0;
            apdu.datalen = 0;
            apdu.data = null();
        }
        else {
            // end_offset (not included; i.e. byte at that address doesn't get erased)
            unsafe { copy_nonoverlapping((idx + count).to_be_bytes().as_ptr(), end_offset.as_mut_ptr(), 2); }
            apdu.data = end_offset.as_ptr();
        }

        rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
        rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
        if rv != SC_SUCCESS {
            if cfg!(log) {
                wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(b"#### Failed to erase binary\0")
                    .unwrap());
            }
            return rv;
        }
        i32::from(count)
    }
}

/*
 * What it does
 * @apiNote
 * @param
 * @return
 */
extern "C" fn acos5_card_ctl(card_ptr: *mut sc_card, command: c_ulong, data_ptr: *mut c_void) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun   = CStr::from_bytes_with_nul(b"acos5_card_ctl\0").unwrap();
    if cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(CALLED).unwrap());
    }
    if data_ptr.is_null() && ![SC_CARDCTL_LIFECYCLE_SET, SC_CARDCTL_ACOS5_HASHMAP_SET_FILE_INFO].contains(&command)
    { return SC_ERROR_INVALID_ARGUMENTS; }

    match command {
        SC_CARDCTL_LIFECYCLE_SET =>
            SC_ERROR_NOT_SUPPORTED, // see sc_pkcs15init_bind
        SC_CARDCTL_GET_SERIALNR =>
            {
                let serial_number = match get_serialnr(card) {
                    Ok(val) => val,
                    Err(e) => return e,
                };
                unsafe { *(data_ptr as *mut sc_serial_number) = serial_number };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_GET_COUNT_FILES_CURR_DF =>
            {
                let count_files_curr_df = match get_count_files_curr_df(card) {
                    Ok(val) => val,
                    Err(e) => return e,
                };
                unsafe { *(data_ptr as *mut u16) = count_files_curr_df };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_GET_FILE_INFO =>
            {
                let file_info_ptr = data_ptr as *mut CardCtlArray8;
                let reference = unsafe { (*file_info_ptr).reference };
                let file_info = match get_file_info(card, reference) {
                    Ok(val) => val,
                    Err(e) => return e,
                };
                unsafe { (*file_info_ptr).value = file_info };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_GET_FREE_SPACE =>
            {
                let free_space = match get_free_space(card) {
                    Ok(val) => val,
                    Err(e) => return e,
                };
                unsafe { *(data_ptr as *mut c_uint) = free_space };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_GET_IDENT_SELF =>
            {
                let is_hw_acos5 = match get_ident_self(card) {
                    Ok(val) => val,
                    Err(e) => return e,
                };
                unsafe { *(data_ptr as *mut bool) = is_hw_acos5 };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_GET_COS_VERSION =>
            {
                let cos_version = match get_cos_version(card) {
                    Ok(val) => val,
                    Err(e) => return e,
                };
                unsafe { (*(data_ptr as *mut CardCtlArray8)).value = cos_version };
                SC_SUCCESS
            },


        SC_CARDCTL_ACOS5_GET_ROM_MANUFACTURE_DATE =>
            {
                let manufacture_date = if card.type_ != SC_CARD_TYPE_ACOS5_64_V3 { return SC_ERROR_NO_CARD_SUPPORT; }
                    else {
                        match get_manufacture_date(card) {
                            Ok(val) => val,
                            Err(e) => return e,
                        }
                    };
                unsafe { *(data_ptr as *mut c_uint) = manufacture_date };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_GET_ROM_SHA1 =>
            {
                let rom_sha1 = if card.type_ == SC_CARD_TYPE_ACOS5_64_V2 { return SC_ERROR_NO_CARD_SUPPORT; }
                    else {
                        match get_rom_sha1(card) {
                            Ok(val) => val,
                            Err(e) => return e,
                        }
                    };
                unsafe { (*(data_ptr as *mut CardCtlArray20)).value = rom_sha1 };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_GET_OP_MODE_BYTE =>
            {
                let op_mode_byte = if card.type_ == SC_CARD_TYPE_ACOS5_64_V2 { return SC_ERROR_NO_CARD_SUPPORT; }
                    else {
                        match get_op_mode_byte(card) {
                            Ok(val) => val,
                            Err(e) => return e,
                        }
                    };
                unsafe { *(data_ptr as *mut u8) = op_mode_byte };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_GET_FIPS_COMPLIANCE =>
            {
                if card.type_ == SC_CARD_TYPE_ACOS5_64_V2 { return SC_ERROR_NO_CARD_SUPPORT; }
                let is_fips_compliant = match get_fips_compliance(card) {
                    Ok(val) => val,
                    Err(e) => return e,
                };
                unsafe { *(data_ptr as *mut bool) = is_fips_compliant };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_GET_PIN_AUTH_STATE =>
            {
                if card.type_ != SC_CARD_TYPE_ACOS5_64_V3 { return SC_ERROR_NO_CARD_SUPPORT; }

                let pin_auth_state_ptr = data_ptr as *mut CardCtlAuthState;
                let reference = unsafe { (*pin_auth_state_ptr).reference };
                let pin_auth_state = match get_pin_auth_state(card, reference) {
                    Ok(val) => val,
                    Err(e) => return e,
                };
                unsafe { (*pin_auth_state_ptr).value = pin_auth_state };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_GET_KEY_AUTH_STATE =>
            {
                if card.type_ != SC_CARD_TYPE_ACOS5_64_V3 { return SC_ERROR_NO_CARD_SUPPORT; }

                let key_auth_state_ptr = data_ptr as *mut CardCtlAuthState;
                let reference = unsafe { (*key_auth_state_ptr).reference };
                let key_auth_state = match get_key_auth_state(card, reference) {
                    Ok(val) => val,
                    Err(e) => return e,
                };
                unsafe { (*key_auth_state_ptr).value = key_auth_state };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_HASHMAP_GET_FILE_INFO =>
            {
                let files_hashmap_info_ptr = data_ptr as *mut CardCtlArray32;
                let key = unsafe { (*files_hashmap_info_ptr).key };
                let files_hashmap_info = match get_files_hashmap_info(card, key) {
                    Ok(val) => val,
                    Err(e) => return e,
                };
                unsafe { (*files_hashmap_info_ptr).value = files_hashmap_info };
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_HASHMAP_SET_FILE_INFO =>
            {
                update_hashmap(card);
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_SDO_CREATE =>
                acos5_create_file(card, data_ptr as *mut sc_file),
        SC_CARDCTL_ACOS5_SDO_GENERATE_KEY_FILES_INJECT_GET =>
            {
                let dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
                unsafe { *(data_ptr as *mut CardCtl_generate_inject_asym) = dp.agi };
                card.drv_data = Box::into_raw(dp) as *mut c_void;
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_SDO_GENERATE_KEY_FILES_INJECT_SET =>
            {
                let mut dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
                dp.agi = unsafe { *(data_ptr as *mut CardCtl_generate_inject_asym) };
                card.drv_data = Box::into_raw(dp) as *mut c_void;
                SC_SUCCESS
            },
        SC_CARDCTL_ACOS5_SDO_GENERATE_KEY_FILES =>
            /* suppose select_file, authenticate, (possibly setting MSE) etc. was done already */
            generate_asym(card, unsafe { &mut *(data_ptr as *mut CardCtl_generate_crypt_asym) }),
        SC_CARDCTL_ACOS5_ENCRYPT_ASYM =>
            /* suppose select_file, authenticate, (possibly setting MSE) etc. was done already */
            encrypt_asym(card, unsafe { &mut *(data_ptr as *mut CardCtl_generate_crypt_asym) }, false),
        SC_CARDCTL_ACOS5_ENCRYPT_SYM |
        SC_CARDCTL_ACOS5_DECRYPT_SYM     =>
            {
                let crypt_sym_data = unsafe { &mut *(data_ptr as *mut CardCtl_crypt_sym) };
                if !logical_xor(crypt_sym_data.outdata_len > 0, !crypt_sym_data.outfile.is_null())  ||
                   !logical_xor(crypt_sym_data.indata_len  > 0, !crypt_sym_data.infile.is_null())   ||
                   ![8_u8, 16].contains(&crypt_sym_data.block_size)  ||
                   ![BLOCKCIPHER_PAD_TYPE_ZEROES, BLOCKCIPHER_PAD_TYPE_ONEANDZEROES, BLOCKCIPHER_PAD_TYPE_ONEANDZEROES_ACOS5_64,
                        BLOCKCIPHER_PAD_TYPE_PKCS5, BLOCKCIPHER_PAD_TYPE_ANSIX9_23/*, BLOCKCIPHER_PAD_TYPE_W3C*/]
                        .contains(&crypt_sym_data.pad_type)
//                    || crypt_sym_data.iv != [0u8; 16]
                { return SC_ERROR_INVALID_ARGUMENTS; }

                if sym_en_decrypt(card, crypt_sym_data) > 0 {SC_SUCCESS} else {SC_ERROR_KEYPAD_MSG_TOO_LONG}
            },
/*
        SC_CARDCTL_ACOS5_CREATE_MF_FILESYSTEM =>
            {
                let pins_data = unsafe { (*(data_ptr as *mut CardCtlArray20)).value };
                /*
                Format of pins in pins_data:
                pins_data[0] :        SOPIN length (max 8), stored in pins_data[1..9]
                pins_data[1..1+len] : SOPIN
                pins_data[10] :        PUK of SOPIN length (max 8), stored in pins_data[11..19]
                pins_data[11..11+len] : PUK of SOPIN
                */
                let sopin = &pins_data[1..1+pins_data[0] as usize];
                let sopuk = &pins_data[11..11+pins_data[10] as usize];
                create_mf_file_system(card, sopin, sopuk);
                SC_SUCCESS
            },
*/
        _   => SC_ERROR_NO_CARD_SUPPORT
    } // match command as c_uint
} // acos5_card_ctl

/*
 * What it does
 * @apiNote
 * @param
 * @return
 */
extern "C" fn acos5_select_file(card_ptr: *mut sc_card, path_ptr: *const sc_path, file_out_ptr: *mut *mut sc_file) -> c_int
{
/*
  Basically, the iso implementation for select_file can work for acos (and always will finally be called), but only if given appropriate parameters.
  A small part of the following select_file implementation is dedicated to solve that, heading: use path.type_ == SC_PATH_TYPE_FILE_ID only.
  But other requirements make the implementation quite complex:
  1. It's necessary to ensure, that the file selected really resides at the given/selected location (path): If acos doesn't find a file within the selected directory,
     it will look-up several other paths, thus may find another one, not intended to be selected (acos allows duplicate file ids, given the containing directories differ).
     There is no way other than disallowing duplicate file/directory ids by the driver and to ensure rule compliance, also when updating by create_file and delete_file.
     Function acos5_init does invoke scanning the card's file system and populate a hash map with i.a. File Information from 'Get Card Info';
     The 'original' 8 bytes (unused will be replaced by other values) are: {FDB, DCB, FILE ID, FILE ID, SIZE or MRL, SIZE or NOR, SFI, LCSI}> to hold all file ids as key,
     and will reject even a matching card that contains file id duplicate(s).
     TODO this is not enforced currently

  2. The access control implemented by acos also is quite complex: Security Attributes Compact (SAC) and Security Attributes Expanded (SAE) and boils down to this:
     Purely by selecting a file/directory, the information about 'rights for acos commands to be allowed to execute' is not complete but must be looked up, different for each directory.
     Thus it suggests itself to also employ a table like structure holding that information: On each selection of a directory, a look-up will be performed if the info is available, otherwise
     retrieved and stored to the table. Any commands that alter the relevant info source (Security Environment File and it's records) must also update the look up table.
     The source for SAE is coded within the directory's header meta data (immutable as long as the directory exists) and may also refer to the Security Environment File (with mutable data).

  3. As preface: acos uses the select command also for extraordinary tasks like 'Clear the internal memory collecting Control Reference Templates (CRT)' or revoke PIN/KEY access rigths etc.
     which must be emitted in order to take effect. On the other hand, with a simplistic impl. of select_file, it turns out that many select commands are superfluous: E.g. coming from selected path
     3F00410043004305 in order to select 3F00410043004307 (both files in the same directory) the simple impl. will select in turn 3F00, 4100, 4300 and finally 4307,
     though for acos it would be sufficient to issue select 4307 right away.
     Thus there will be some logic required (making use of acos 'search files at different places' capability to speed up performance and distinguish from cases,
     where selects must not be stripped off (i.e. when the selection path ends at a directory - even if it's the same as the actual - selection must not be skipped).
     For this, the info from 1. comes in handy.

     8.2.1.  Verify PIN
This command is used to submit a PIN code to gain access rights. Access rights achieved will be
invalidated when a new DF is selected. Command submission with P3=0 will return the remaining
number of retries left for the PIN.

There is an undocumented order dependence:
This works       :  select_file, verify_pin, set_security_env
This doesn't work:  select_file, set_security_env, verify_pin

     8.4.2.1.  Set Security Environment
To clear the accumulated CRT’s, issue a SELECT FILE command

  Format of HashMap<KeyTypeFiles, ValueTypeFiles> :
  pub type KeyTypeFiles   = u16;
  //                                 path (absolute)                 File Info        scb8                SACinfo
  pub type ValueTypeFiles = (Option<[u8; SC_MAX_PATH_SIZE]>, Option<[u8; 8]>, Option<[u8; 8]>, Option<Vec<SACinfo>>);
  1. tuple element: path, the absolute path, 16 bytes
  2. tuple element: originally it contains File Information from acos command 'Get Card Info': {FDB, DCB, FILE ID, FILE ID, SIZE or MRL, SIZE or NOR, SFI, LCSI}
                    FDB: the File Descriptor Byte
                   *DCB (unused by acos): will be replaced by path.len of 1. tuple element, the len actually used for the path
                    FILE ID: 2 bytes containing the file id, the same as hash map entry's key
                   *SIZE or MRL: For record-based file types, the Max.Record Length, otherwise (if it's not MF/DF), the MSB of file size;
                                 for MF/DF, this byte holds MSB of associated SE file id
                   *SIZE or NOR: For record-based file types, the Number Of Records created for this file, otherwise (if it's not MF/DF), the LSB of file size;
                                 for MF/DF, this byte holds LSB of associated SE file id
                   *SFI  Short file Identifier (unused by the driver and opensc?): will be replaced by PKCS#15 file type
                    LCSI: Life Cycle Status Integer
  3. tuple element: scb8, 8 Security Condition Bytes after conversion, i.e. scb8[3..8] refer to Deactivate/SC_AC_OP_INVALIDATE, Activate/SC_AC_OP_REHABILITATE, Terminate/SC_AC_OP_LOCK, SC_AC_OP_DELETE_SELF, Unused Byte
(later here: sm_mode8: Coding Secure Messaging required or not, same operations referred to by position as in scb8, i.e. an SCB 0x45 will have set at same position in sm_mode8: Either SM_MODE_CCT or SM_MODE_CCT_AND_CT_SYM, depending on content of Security Environment file record id 5)
  4. tuple element: SACinfo referring to SAC (SAE is not covered so far)
                    Each vector element covers the content of Security Environment file's record, identified by reference==record's SE id (should be the same as record number)
                    SACinfo is stored for DF/MF only, each of which have different vectors
(later here: SaeInfo)




  If file_out_ptr != NULL then, as long as iso7816_select_file behavior is not mimiced completely, it's important to call iso7816_select_file finally: It will call process_fci
  and evaluate the file header bytes !
  Main reasons why this function exists:
    acos supports P2==0 and (P1==0 (SC_PATH_TYPE_FILE_ID) or P1==4 (SC_PATH_TYPE_DF_NAME)) only
  - Not all path.type_ are handled correctly for ACOS5 by iso7816_select_file (depending also on file_out_ptr):
    SC_PATH_TYPE_FILE_ID can be handled by iso7816_select_file (for file_out_ptr == NULL sets incorrectly sets p2 = 0x0C, but then on error sw1sw2 == 0x6A86 corrects to p2=0
    SC_PATH_TYPE_PATH will set P1 to 8, unknown by acos, but can be worked around splitting the path into len=2 temporary path segments with SC_PATH_TYPE_FILE_ID
*/
    if card_ptr.is_null() || path_ptr.is_null() {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card = unsafe { &mut *card_ptr };
    let path_ref = unsafe { & *path_ptr };
    // first setting of  card.cache.current_path.len  done in acos5_init
    if card.cache.current_path.len==0 || (path_ref.type_==SC_PATH_TYPE_FILE_ID && path_ref.len!=2) ||
        !(path_ref.len>=2 && path_ref.len<=16 && path_ref.len%2==0) || is_impossible_file_match(path_ref) {
        return SC_ERROR_INVALID_ARGUMENTS;
    }

    let dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
    let does_mf_exist = dp.does_mf_exist;
    let target_file_id = file_id_from_path_value(&path_ref.value[..path_ref.len]); // wrong result for SC_PATH_TYPE_DF_NAME, but doesn't matter
    /* if we are not called from within "is_running_init==true", then we must be sure that dp.files.2 is Some, i.e. we know the scb8 of target file when returning from select_file
       We don't know what comes next after select_file: it may be a cmd that enforces using SM (retrievable from scb8) */
    let need_to_process_fci = !dp.is_running_init && dp.files.contains_key(&target_file_id) && dp.files[&target_file_id].2.is_none();
    card.drv_data = Box::into_raw(dp) as *mut c_void;
    if !does_mf_exist { return SC_ERROR_NOT_ALLOWED;}

    match path_ref.type_ {
        SC_PATH_TYPE_PATH     => select_file_by_path(card, path_ref, file_out_ptr, need_to_process_fci),
        SC_PATH_TYPE_DF_NAME  => tracking_select_file(card, path_ref, file_out_ptr,
                                                      if file_out_ptr.is_null() {true} else {false}),
        SC_PATH_TYPE_FILE_ID  => tracking_select_file(card, path_ref, file_out_ptr, need_to_process_fci),
        /*SC_PATH_TYPE_PATH_PROT | SC_PATH_TYPE_FROM_CURRENT | SC_PATH_TYPE_PARENT  => SC_ERROR_NO_CARD_SUPPORT,*/
        _  => SC_ERROR_NO_CARD_SUPPORT,
    }
}

/*
Specific Return Status Code of cos5 Get Response
SW1 SW2   Definition
6b 00h    Wrong P1 or P2. Value must be 00h.
6C XXh    Incorrect P3. Value must be XXh.       actually OpenSC catches this and retransmits once with corrected XX
6A 88h    No data available
*/

/* get_response:   iso7816_get_response, limited to read max. 0xFF/(0x100 with card.max_recv_size = SC_READER_SHORT_APDU_MAX_RECV_SIZE;) bytes, does work,
        see the impl. for more than 256 bytes: my_get_response
        get_response returns how many more bytes there are still to retrieve by a following call to get_response */
/*
 * What it does
 * @apiNote  ATTENTION SPECIAL MEANING of @return
 * @param  card
 * @param  count INOUT IN  how many bytes are expected that can be fetched;
                       OUT how many bytes actually were fetched by this call and were written to buf
 * @param  buf
 * @return how many bytes can be expected to be fetched the next time, this function get's called: It's a guess only
 */
#[cfg_attr(feature = "cargo-clippy", allow(clippy::suspicious_else_formatting))]
extern "C" fn acos5_get_response(card_ptr: *mut sc_card, count_ptr: *mut usize, buf_ptr: *mut c_uchar) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || count_ptr.is_null() || buf_ptr.is_null() {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let cnt_in = unsafe { *count_ptr };
    assert!(cnt_in <= 256);
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun = CStr::from_bytes_with_nul(b"acos5_get_response\0").unwrap();
    let fmt = CStr::from_bytes_with_nul(b"called with: *count: %zu\0").unwrap();
    let fmt_1 = CStr::from_bytes_with_nul(b"returning with: *count: %zu, rv: %d\0").unwrap();
    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(), fun, cnt_in, fmt);
    }

    card.max_recv_size = SC_READER_SHORT_APDU_MAX_RECV_SIZE;
    /* request at most max_recv_size bytes */
    let rlen = std::cmp::min(cnt_in, me_get_max_recv_size(card));
    unsafe{ *count_ptr = 0 };
//println!("### acos5_get_response rlen: {}", rlen);
    let command = [0, 0xC0, 0x00, 0x00, 0xFF]; // will replace le later; the last byte is a placeholder only for sc_bytes2apdu_wrapper
    let mut apdu = sc_apdu::default();
    let mut rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
    assert_eq!(rv, SC_SUCCESS);
    assert_eq!(apdu.cse, SC_APDU_CASE_2_SHORT);
    apdu.le      = rlen;
    apdu.resplen = rlen;
    apdu.resp    = buf_ptr;
    /* don't call GET RESPONSE recursively */
    apdu.flags  |= SC_APDU_FLAGS_NO_GET_RESP as c_ulong;

    rv = unsafe { sc_transmit_apdu(card, &mut apdu) };
//    LOG_TEST_RET(card->ctx, rv, "APDU transmit failed");
    if rv != SC_SUCCESS {
        if      apdu.sw1==0x6B && apdu.sw2==0x00 {
println!("### acos5_get_response returned 0x6B00:   Wrong P1 or P2. Value must be 00h.");
        }
        else if apdu.sw1==0x6A && apdu.sw2==0x88 {
println!("### acos5_get_response returned 0x6A88:   No data available.");
        }
        else {
println!("### acos5_get_response returned apdu.sw1: {:X}, apdu.sw2: {:X}   Unknown error code", apdu.sw1, apdu.sw2);
        }
        if cfg!(log) {
            wr_do_log_tu(card_ctx, f_log, line!(), fun, unsafe { *count_ptr }, rv, fmt_1);
        }
        card.max_recv_size = SC_READER_SHORT_APDU_MAX_SEND_SIZE;
        return rv;
    }
    if !(apdu.sw1==0x6A && apdu.sw2==0x88) && apdu.resplen == 0 {
//    LOG_FUNC_RETURN(card->ctx, sc_check_sw(card, apdu.sw1, apdu.sw2));
        rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
        if cfg!(log) {
            wr_do_log_tu(card_ctx, f_log, line!(), fun, unsafe { *count_ptr }, rv, fmt_1);
        }
        card.max_recv_size = SC_READER_SHORT_APDU_MAX_SEND_SIZE;
        return rv;
    }

    unsafe { *count_ptr = apdu.resplen };

    //TODO temporarily allow suspicious_else_formatting
    if      apdu.sw1==0x90 && apdu.sw2==0x00 {
        /* for some cos5 commands, it's NOT necessarily true, that status word 0x9000 signals "no more data to read" */
        rv = if get_is_running_cmd_long_response(card) {set_is_running_cmd_long_response(card, false); 256} else {0 /* no more data to read */};
        /* switching of here should also work for e.g. a 3072 bit key:
           The first  invocation by sc_get_response is with *count_ptr==256 (set by sc_get_response)
           The second invocation by sc_get_response is with *count_ptr==256 (got from rv, line above), fails, as the correct rv should have been 128,
             but the failure doesn't crawl up to this function, as a retransmit with corrected value 128 will be done in the low sc_transmit layer;
             thus there should be only 1 situation when (apdu.sw1==0x6A && apdu.sw2==0x88) get's to this function: For a 2048 bit RSA  key operation with is_running_cmd_long_response==true
            */
    }
/*
    else if apdu.sw1 == 0x61 { // this never get's returned by command
        rv = if apdu.sw2 == 0 {256} else {apdu.sw2 as c_int};    /* more data to read */
    }
    else if apdu.sw1 == 0x62 && apdu.sw2 == 0x82 { // this never get's returned by command
        rv = 0; /* Le not reached but file/record ended */
    }
*/
    else if apdu.sw1==0x6A && apdu.sw2==0x88 {
        rv = 0;
    }
    else {
        rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
    }
    if cfg!(log) {
        wr_do_log_tu(card_ctx, f_log, line!(), fun, unsafe { *count_ptr }, rv, fmt_1);
    }

    card.max_recv_size = SC_READER_SHORT_APDU_MAX_SEND_SIZE;
    rv
}

/*
 * Get data from card's PRNG; as card's command supplies a fixed number of 8 bytes, some administration is required for count!= multiple of 8
 * @apiNote
 * @param count how many bytes are requested from RNG
 * @return MUST return the number of challenge bytes stored to buf
 */
extern "C" fn acos5_get_challenge(card_ptr: *mut sc_card, buf_ptr: *mut c_uchar, count: usize) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || buf_ptr.is_null() || count > 1024 {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun = CStr::from_bytes_with_nul(b"acos5_get_challenge\0").unwrap();
    let fmt = CStr::from_bytes_with_nul(b"called with request for %zu bytes\0").unwrap();
    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(), fun, count, fmt);
    }
    let func_ptr = unsafe { (*(*sc_get_iso7816_driver()).ops).get_challenge.unwrap() };
    let is_count_multiple8 =  count%8 == 0;
    let loop_count = count/8 + (if is_count_multiple8 {0_usize} else {1_usize});
    let mut len_rem = count;
    for i in 0..loop_count {
        if i+1<loop_count || is_count_multiple8 {
            let rv = unsafe { func_ptr(card, buf_ptr.add(i*8), 8) };
            if rv != 8 { return rv; }
            len_rem -= 8;
        }
        else {
            assert!(len_rem>0 && len_rem<8);
            let mut buf_temp = [0; 8];
            let rv = unsafe { func_ptr(card, buf_temp.as_mut_ptr(), 8) };
            if rv != 8 { return rv; }
            unsafe { copy_nonoverlapping(buf_temp.as_ptr(), buf_ptr.add(i*8), len_rem) };
        }
    }
/*
    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(), fun, count, CStr::from_bytes_with_nul(b"returning with requested %zu bytes supplied\0").unwrap());
    }
*/
    count as c_int
}

/* currently refers to pins only, but what about authenticated keys */
extern "C" fn acos5_logout(card_ptr: *mut sc_card) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun   = CStr::from_bytes_with_nul(b"acos5_logout\0").unwrap();
    if cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(CALLED).unwrap());
    }

    let command = [0x80, 0x2E, 0x00, 0x00];
    let mut apdu = sc_apdu::default();
    let mut rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
    assert_eq!(rv, SC_SUCCESS);
    assert_eq!(apdu.cse, SC_APDU_CASE_1);

//    let aid = null_mut();
    let mut p15card = null_mut();
    rv = unsafe { sc_pkcs15_bind(card, null_mut(), &mut p15card) };
    if rv < SC_SUCCESS {
        if cfg!(log) {
            wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(b"failed: sc_pkcs15_bind\0").unwrap());
        }
        return rv;
    }
    assert!(!p15card.is_null());
    let mut p15objects : [*mut sc_pkcs15_object; 10] = [null_mut(); 10]; // TODO there should be less than 10 AUTH_PIN
    let nn_objs = unsafe { sc_pkcs15_get_objects(p15card, SC_PKCS15_TYPE_AUTH_PIN, &mut p15objects[0], 10) } as usize;
    for item in p15objects.iter().take(nn_objs) {
        let auth_info_ref = unsafe { &*((*(*item)).data as *mut sc_pkcs15_auth_info) };
        apdu.p2 = unsafe { auth_info_ref.attrs.pin.reference } as u8; //*pin_reference;
        rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
        rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
        if rv != SC_SUCCESS {
            if cfg!(log) {
                wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul
                    (b"ACOS5 'Logout' failed\0").unwrap());
            }
            return SC_ERROR_KEYPAD_MSG_TOO_LONG;
        }
    }
    rv = unsafe { sc_pkcs15_unbind(p15card) }; // calls sc_pkcs15_pincache_clear
    if rv < SC_SUCCESS && cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(b"failed: sc_pkcs15_unbind\0").unwrap());
    }
    SC_SUCCESS
}


/* TODO this isn't yet completed: 1. the hashmap-entry/path+fileinfo must be set and 2. there is more to do for MF/DF */
/* expects some entries in file, see acos5_construct_fci */
extern "C" fn acos5_create_file(card_ptr: *mut sc_card, file_ptr: *mut sc_file) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || file_ptr.is_null() || unsafe {(*file_ptr).id==0} {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let file = unsafe { &mut *file_ptr };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun   = CStr::from_bytes_with_nul(b"acos5_create_file\0").unwrap();
    let rv;
    if cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(CALLED).unwrap());
    }

    let dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
    if dp.files.contains_key(&(file.id as u16)) {
        card.drv_data = Box::into_raw(dp) as *mut c_void;
        rv = SC_ERROR_NOT_ALLOWED;
        unsafe { wr_do_log_sds(card_ctx, f_log, line!(), fun,CStr::from_bytes_with_nul(b"### Duplicate file id disallowed by the driver ! ###\0")
            .unwrap().as_ptr(), rv, sc_strerror(rv), CStr::from_bytes_with_nul(b"%s: %d (%s)\n\0").unwrap()) };
        return rv;
    }
    card.drv_data = Box::into_raw(dp) as *mut c_void;

    if file.path.len == 0 {
        let current_path_df = current_path_df(card);
        let len = current_path_df.len();
        let mut path = sc_path { type_: SC_PATH_TYPE_PATH, len: len+2, ..sc_path::default() };
        unsafe { copy_nonoverlapping(current_path_df.as_ptr(),  path.value.as_mut_ptr(), len); }
        unsafe { copy_nonoverlapping((file.id as u16).to_be_bytes().as_ptr(),  path.value.as_mut_ptr().add(len), 2); }
        file.path = path;
    }

    /* iso7816_create_file calls acos5_construct_fci */
    let func_ptr = unsafe { (*(*sc_get_iso7816_driver()).ops).create_file.unwrap() };
    rv = unsafe { func_ptr(card, file_ptr) };

    if rv != SC_SUCCESS {
        if cfg!(log) {
            wr_do_log_t(card_ctx, f_log, line!(), fun, rv,
                        CStr::from_bytes_with_nul(b"acos5_create_file failed. rv: %d\0").unwrap());
        }
    }
    else {
        let file_ref : &sc_file = file;
        let mut dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
        dp.files.insert(file_ref.id as u16, (file_ref.path.value, [0, 0, 0, 0, 0, 0, 0xFF, 1], None, None, None));
        let mut x = dp.files.get_mut(&(file_ref.id as u16)).unwrap();
        x.1[0] = file_ref.type_ as c_uchar;
        x.1[1] = file_ref.path.len as c_uchar;
        x.1[2] = file_ref.path.value[file_ref.path.len-2];
        x.1[3] = file_ref.path.value[file_ref.path.len-1];
        if [FDB_LINEAR_FIXED_EF, FDB_LINEAR_VARIABLE_EF, FDB_CYCLIC_EF, FDB_CHV_EF, FDB_SYMMETRIC_KEY_EF, FDB_PURSE_EF, FDB_SE_FILE].contains(&(file_ref.type_ as c_uchar) ) {
            x.1[4] = file_ref.record_length as c_uchar;
            x.1[5] = file_ref.record_count  as c_uchar;
        }
        else if [FDB_TRANSPARENT_EF, FDB_RSA_KEY_EF, FDB_ECC_KEY_EF].contains(&(file_ref.type_ as c_uchar) ) {
            unsafe { copy_nonoverlapping((file_ref.size as u16).to_be_bytes().as_ptr(), x.1.as_mut_ptr().add(4), 2); }
        }
        else { // MF/DF
            unsafe { copy_nonoverlapping(((file_ref.id+3) as u16).to_be_bytes().as_ptr(), x.1.as_mut_ptr().add(4), 2); }
        }
        card.drv_data = Box::into_raw(dp) as *mut c_void;

        if cfg!(log) {
            wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.id,
                        CStr::from_bytes_with_nul(b"file_id %04X added to hashmap\0").unwrap());
        }
    }
    rv
}

/* opensc-explorer doesn't select first
iso7816_delete_file: condition: (path->type == SC_PATH_TYPE_FILE_ID && (path->len == 0 || path->len == 2))
*/
/* expects a path of type SC_PATH_TYPE_FILE_ID and a path.len of 2 or 0 (0 means: delete currently selected file) */
/* even with a given path with len==2, acos expects a select_file ! */
extern "C" fn acos5_delete_file(card_ptr: *mut sc_card, path_ref_ptr: *const sc_path) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || path_ref_ptr.is_null() {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let path_ref= unsafe { &*path_ref_ptr };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun   = CStr::from_bytes_with_nul(b"acos5_delete_file\0").unwrap();
    if cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(CALLED).unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, unsafe{sc_dump_hex(card.cache.current_path.value.as_ptr(), card.cache.current_path.len)}, CStr::from_bytes_with_nul(b"card.cache.current_path %s\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, unsafe{sc_dump_hex(path_ref.value.as_ptr(), path_ref.len)}, CStr::from_bytes_with_nul(b"path_ref %s\0").unwrap());
    }

    let file_id = if path_ref.len == 0 { file_id_from_cache_current_path(card) }
                        else                 { file_id_from_path_value(&path_ref.value[..path_ref.len]) };
////println!("file_id: {:X}", file_id);

    let dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
    if !dp.files.contains_key(&file_id) {
println!("file_id: {:X} is not a key of hashmap dp.files", file_id);
        card.drv_data = Box::into_raw(dp) as *mut c_void;
        return -1;
    }
    let x = &dp.files[&file_id];
    let need_to_select_or_process_fci = x.2.is_none() || file_id != file_id_from_cache_current_path(card);
    let mut scb_delete_self = if !need_to_select_or_process_fci {x.2.unwrap()[6]} else {0xFF};
    card.drv_data = Box::into_raw(dp) as *mut c_void;

    let mut rv;
    if need_to_select_or_process_fci {
        let mut file_out_ptr_tmp = null_mut();
        rv = unsafe { sc_select_file(card, path_ref, &mut file_out_ptr_tmp) };
        if !file_out_ptr_tmp.is_null() {
            unsafe { sc_file_free(file_out_ptr_tmp) };
        }
        if rv != SC_SUCCESS {
            return rv;
        }
        let dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
        scb_delete_self = dp.files[&file_id].2.unwrap()[6];
        card.drv_data = Box::into_raw(dp) as *mut c_void;
    }

//println!("acos5_delete_file  scb_delete_self: {}", scb_delete_self);
    if scb_delete_self == 0xFF {
        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(
            b"No delete_file will be done: The file has acl NEVER DELETE_SELF\0").unwrap());
        rv = SC_ERROR_SECURITY_STATUS_NOT_SATISFIED;
    }
    else if (scb_delete_self & 0x40) == 0x40 { // sc_select_file was done, as SM doesn't accept path.len==2
        let res_se_sm = se_get_is_scb_suitable_for_sm_has_ct(card, file_id, scb_delete_self & 0x0F);
        if !res_se_sm.0 {
            wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(
                b"No delete_file will be done: The file has acl SM-protected DELETE_SELF\0").unwrap());
            rv = SC_ERROR_SECURITY_STATUS_NOT_SATISFIED;
        }
        else {
            rv = sm_delete_file(card);
        }
    }
    else {
        let mut path = sc_path { type_: SC_PATH_TYPE_FILE_ID, len: std::cmp::min(path_ref.len, 2), ..*path_ref };// *path_ref;//= unsafe { &*path_ref_ptr };
        if path.len == 2 {
            unsafe { copy_nonoverlapping(path_ref.value.as_ptr().add(path_ref.len-2), path.value.as_mut_ptr(), 2) };
        }
        let func_ptr = unsafe { (*(*sc_get_iso7816_driver()).ops).delete_file.unwrap() };
        rv = unsafe { func_ptr(card, &path) };
    }
////
    if rv != SC_SUCCESS {
        if cfg!(log) {
            wr_do_log_t(card_ctx, f_log, line!(), fun, rv,
                        CStr::from_bytes_with_nul(b"acos5_delete_file failed. rv: %d\0").unwrap());
        }
    }
    else {
        let mut dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
        let rm_result = dp.files.remove(&file_id);
        assert!(rm_result.is_some());
        card.drv_data = Box::into_raw(dp) as *mut c_void;
        assert!(card.cache.current_path.len > 2);
        card.cache.current_path.len   -= 2;
//println!("acos5_delete_file  card.cache.current_path: {:X?}", &card.cache.current_path.value[..card.cache.current_path.len]);
        if cfg!(log) {
            wr_do_log_t(card_ctx, f_log, line!(), fun, file_id,
                        CStr::from_bytes_with_nul(b"file_id %04X deleted from hashmap\0").unwrap());
        }
    }
    rv
}

/*
 * what's expected are the file IDs of files within the selected directory.
 * as opensc-tool provides as buf u8[SC_MAX_APDU_BUFFER_SIZE], max 130 files for each directory can be listed
 * @param  card    INOUT
 * @param  buf     INOUT
 * @param  buflen  IN
 * @return         number of bytes put into buf <= buflen
*/
/*
 * What it does
 * @apiNote
 * @param
 * @return
 */
extern "C" fn acos5_list_files(card_ptr: *mut sc_card, buf_ptr: *mut c_uchar, buflen: usize) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || buf_ptr.is_null() || buflen<2 {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun   = CStr::from_bytes_with_nul(b"acos5_list_files\0").unwrap();
    let fmt   = CStr::from_bytes_with_nul(CALLED).unwrap();
    if cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, fmt);
    }

    /* retrieve the number of files in the currently selected directory*/
    let numfiles = match get_count_files_curr_df(card) {
        Ok(val) => if val > (buflen/2) as u16 {(buflen/2) as u16} else {val},
        Err(e) => return e,
    };
    if numfiles > 0 {
        let mut dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };

        /* collect the IDs of files in the currently selected directory, restrict to max. 255, because addressing has 1 byte only */
        for i  in 0.. std::cmp::min(numfiles as usize, 255) { // [0..254] or [1..255]
            let mut rbuf = match get_file_info(card, i as u8 + if card.type_==SC_CARD_TYPE_ACOS5_EVO_V4 {1_u8} else {0_u8}) {
                Ok(val) => val,
                Err(e) => {
                    card.drv_data = Box::into_raw(dp) as *mut c_void;
                    return e
                },
            };
            unsafe {
                *buf_ptr.add(i * 2    ) = rbuf[2];
                *buf_ptr.add(i * 2 + 1) = rbuf[3];
            }
            rbuf[6] = match rbuf[0] { // replaces the unused ISO7816_RFU_TAG_FCP_SFI
                FDB_CHV_EF           => PKCS15_FILE_TYPE_PIN,
                FDB_SYMMETRIC_KEY_EF => PKCS15_FILE_TYPE_SECRETKEY,
//                FDB_RSA_KEY_EF       => PKCS15_FILE_TYPE_RSAPRIVATEKEY, // must be corrected for public key files later on
                _                         => PKCS15_FILE_TYPE_NONE, // the default: not relevant for PKCS#15; will be changed for some files later on
            };

            let file_id = u16::from_be_bytes([rbuf[2], rbuf[3]]);

            if dp.is_running_init {
                if dp.files.contains_key(&file_id) {
                    card.drv_data = Box::into_raw(dp) as *mut c_void;
                    let rv = SC_ERROR_NOT_ALLOWED;
                    unsafe { wr_do_log_sds(card_ctx, f_log, line!(), fun,CStr::from_bytes_with_nul(b"### Duplicate file id disallowed by the driver ! ###\0")
                        .unwrap().as_ptr(), rv, sc_strerror(rv), CStr::from_bytes_with_nul(b"%s: %d (%s)\n\0").unwrap()) };
                    return rv;
                }
                dp.files.insert(file_id, ([0; SC_MAX_PATH_SIZE], rbuf, None, None, None));
            }
        } // for
        card.drv_data = Box::into_raw(dp) as *mut c_void;
    }
    i32::from(numfiles)*2
}


/*
 *  Evaluates file header bytes from TLV with T= ISO7816_TAG_FCI or ISO7816_TAG_FCP,
 *  provided from select_file response data (opensc calls this function only from iso7816_select_file)
 *
 *  @apiNote  iso7816_select_file positions buf by calling sc_asn1_read_tag such that the first 2 bytes (Tag 0x6F and
 *            L==buflen are skipped)
 *  @param  card    INOUT
 *  @param  file    INOUT iso7816_select_file allocates a file object, field 'path' assigned
 *  @param  buf     IN    Must point to V[0] of FCI's first TLV
 *  @param  buflen  IN    L of FCI's first TLV
 *  @return         SC_SUCCESS or error code from errors.rs
 */
/*
 * What it does
 * @apiNote
 * @param
 * @return
 */
//TODO temporarily allow cognitive_complexity
#[cfg_attr(feature = "cargo-clippy", allow(clippy::cognitive_complexity))]
extern "C" fn acos5_process_fci(card_ptr: *mut sc_card, file_ptr: *mut sc_file,
                                buf_ref_ptr: *const c_uchar, buflen: usize) -> c_int
{
/*
  Many tags are detected by iso7816_process_fci, but it misses to search for
  0x8C  ISO7816_RFU_TAG_FCP_SAC
  0x8D  ISO7816_RFU_TAG_FCP_SEID
  0xAB  ISO7816_RFU_TAG_FCP_SAE

//  0x82  ISO7816_TAG_FCP_TYPE must be evaluated once more for proprietary EF: SE file : mark it as internal EF: opensc-tool prints only for
//  SC_FILE_TYPE_WORKING_EF, SC_FILE_TYPE_INTERNAL_EF, SC_FILE_TYPE_DF
//  file sizes are missing for structure: linear-fixed and linear-variable
*/
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || file_ptr.is_null() {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let file        = unsafe { &mut *file_ptr };

    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun   = CStr::from_bytes_with_nul(b"acos5_process_fci\0").unwrap();
    let fmt   = CStr::from_bytes_with_nul(CALLED).unwrap();
    if cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, fmt);
    }

    let mut vec_bytes_tag_fcp_sac : Vec<c_uchar> = Vec::with_capacity(8);
    let mut len_bytes_tag_fcp_sac = 0_usize;
    let ptr_bytes_tag_fcp_sac = unsafe { sc_asn1_find_tag(card_ctx, buf_ref_ptr, buflen,
                                                          u32::from(ISO7816_RFU_TAG_FCP_SAC), &mut len_bytes_tag_fcp_sac) };
    assert!(!ptr_bytes_tag_fcp_sac.is_null());
    vec_bytes_tag_fcp_sac.extend_from_slice(unsafe { from_raw_parts(ptr_bytes_tag_fcp_sac, len_bytes_tag_fcp_sac) });
    let scb8 = match convert_bytes_tag_fcp_sac_to_scb_array(vec_bytes_tag_fcp_sac.as_slice()) {
        Ok(scb8)  => scb8,
        Err(e)      => return e,
    };
/*
    let mut buf_vec : Vec<c_uchar> = Vec::with_capacity(90);
    buf_vec.extend_from_slice(unsafe { from_raw_parts(buf_ref_ptr, buflen) });
    println!("buf_vec: {:X?}, scb8: {:X?}", buf_vec, scb8);
*/
    let rv = unsafe { (*(*sc_get_iso7816_driver()).ops).process_fci.unwrap()(card, file, buf_ref_ptr, buflen) };
    assert_eq!(rv, SC_SUCCESS);
/* */
    /* save all the FCI data for future use */
    let rv = unsafe { sc_file_set_prop_attr(file, buf_ref_ptr, buflen) };
    assert_eq!(rv, SC_SUCCESS);
    assert!(file.prop_attr_len>0);
    assert!(!file.prop_attr.is_null());
/* */
    // retrieve FDB FileDescriptorByte and perform some corrective actions
    // if file.type_== 0 || (file.type_!= SC_FILE_TYPE_DF && file.ef_structure != SC_FILE_EF_TRANSPARENT)
    let mut len_bytes_tag_fcp_type = 0_usize;
    let     ptr_bytes_tag_fcp_type = unsafe { sc_asn1_find_tag(card_ctx, buf_ref_ptr, buflen, u32::from(ISO7816_TAG_FCP_TYPE), &mut len_bytes_tag_fcp_type) };
    assert!(!ptr_bytes_tag_fcp_type.is_null()); // It's a mandatory tag
    assert!( len_bytes_tag_fcp_type >=2 );
    let fdb = unsafe { *ptr_bytes_tag_fcp_type };
    if  file.type_ == 0 && fdb == FDB_SE_FILE {
        file.type_ = SC_FILE_TYPE_INTERNAL_EF;
    }
    if file.type_ != SC_FILE_TYPE_DF && file.ef_structure != SC_FILE_EF_TRANSPARENT { // for non-transparent EF multiply MaxRecordLen and NumberOfRecords as a file size hint
//        82, 6, 1C, 0, 0, 30, 0, 1
        assert!(len_bytes_tag_fcp_type >= 5 && len_bytes_tag_fcp_type <= 6);
        #[cfg(    any(v0_17_0, v0_18_0, v0_19_0))]
        { file.record_length = unsafe { *ptr_bytes_tag_fcp_type.add(3) as c_int }; }
        #[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
        { file.record_length = unsafe { usize::from(*ptr_bytes_tag_fcp_type.add(3)) }; }

        #[cfg(    any(v0_17_0, v0_18_0, v0_19_0))]
        { file.record_count  = unsafe { *ptr_bytes_tag_fcp_type.add(len_bytes_tag_fcp_type-1) as c_int }; }
        #[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
        { file.record_count  = unsafe { usize::from(*ptr_bytes_tag_fcp_type.add(len_bytes_tag_fcp_type-1)) }; }

        #[cfg(    any(v0_17_0, v0_18_0, v0_19_0))]
        { file.size = (file.record_length * file.record_count) as usize; }
        #[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
        { file.size =  file.record_length * file.record_count; }
    }

    let mut sefile_id = [0; 2];
    let mut vec_bytes_tag_fcp_sae : Vec<c_uchar> = Vec::with_capacity(32);
    if is_DFMF(fdb) {
        let mut len_bytes_tag_fcp_seid = 0_usize;
        let     ptr_bytes_tag_fcp_seid = unsafe { sc_asn1_find_tag(card_ctx, buf_ref_ptr, buflen,
                                                  u32::from(ISO7816_RFU_TAG_FCP_SEID), &mut len_bytes_tag_fcp_seid) };
        assert!(  !ptr_bytes_tag_fcp_seid.is_null());
        assert_eq!(len_bytes_tag_fcp_seid, 2);
        sefile_id = unsafe { [*ptr_bytes_tag_fcp_seid, *ptr_bytes_tag_fcp_seid.offset(1)] };
//        println!("sefile_id: {:?}", sefile_id);
        let mut len_bytes_tag_fcp_sae = 0_usize;
        let ptr_bytes_tag_fcp_sae = unsafe { sc_asn1_find_tag(card_ctx, buf_ref_ptr, buflen, u32::from(ISO7816_RFU_TAG_FCP_SAE),
                                                              &mut len_bytes_tag_fcp_sae) };
        if !ptr_bytes_tag_fcp_sae.is_null() && len_bytes_tag_fcp_sae>0 {
            vec_bytes_tag_fcp_sae.extend_from_slice(unsafe { from_raw_parts(ptr_bytes_tag_fcp_sae, len_bytes_tag_fcp_sae) });
/*
vec_bytes_tag_fcp_sae: [84, 1, 2C, 97, 0,        // never allow Unblock Pin
                        84, 1, 24, 9E, 1, 42]    // Change Code only via Secure Messaging SCB: 0x42
file_id: 4300
*/
        }
    }

    let mut len_bytes_tag_fcp_lcs = 0;
    let     ptr_bytes_tag_fcp_lcs = unsafe { sc_asn1_find_tag(card_ctx, buf_ref_ptr, buflen,
                                             u32::from(ISO7816_TAG_FCP_LCS), &mut len_bytes_tag_fcp_lcs) };
    assert!(  !ptr_bytes_tag_fcp_lcs.is_null());
    assert_eq!(len_bytes_tag_fcp_lcs, 1);
    let lcsi = unsafe { *ptr_bytes_tag_fcp_lcs };


    /* select_file is always allowed */
    assert_eq!(    SC_SUCCESS, unsafe { sc_file_add_acl_entry(file, SC_AC_OP_SELECT,     SC_AC_NONE, SC_AC_KEY_REF_NONE) } );
    if is_DFMF(fdb) {
        /* list_files is always allowed for MF/DF */
        assert_eq!(SC_SUCCESS, unsafe { sc_file_add_acl_entry(file, SC_AC_OP_LIST_FILES, SC_AC_NONE, SC_AC_KEY_REF_NONE) } );
        /* for opensc-tool also add the general SC_AC_OP_CREATE, which shall comprise both, SC_AC_OP_CREATE_EF and SC_AC_OP_CREATE_DF (added below later)  */
        se_file_add_acl_entry(card, file, scb8[1], SC_AC_OP_CREATE); // Create EF
        se_file_add_acl_entry(card, file, scb8[2], SC_AC_OP_CREATE); // Create DF
    }
    else {
        /* for an EF, acos doesn't distinguish access right update <-> write, thus add SC_AC_OP_WRITE as a synonym to SC_AC_OP_UPDATE */
        se_file_add_acl_entry(card, file, scb8[1], SC_AC_OP_WRITE);
        /* usage of SC_AC_OP_DELETE_SELF <-> SC_AC_OP_DELETE seems to be in confusion in opensc, thus for opensc-tool and EF add SC_AC_OP_DELETE to SC_AC_OP_DELETE_SELF
           My understanding is:
           SC_AC_OP_DELETE_SELF designates the right to delete the EF/DF that contains this right in it's SCB
           SC_AC_OP_DELETE      designates the right of a directory, that a contained file may be deleted; acos calls that Delete Child
        */
        se_file_add_acl_entry(card, file, scb8[6], SC_AC_OP_DELETE);
    }
    /* for RSA key file add SC_AC_OP_GENERATE to SC_AC_OP_CRYPTO */
    if fdb == FDB_RSA_KEY_EF {
        se_file_add_acl_entry(card, file, scb8[2], SC_AC_OP_GENERATE); // MSE/PSO Commands
    }

    let ops_df_mf  = [ SC_AC_OP_DELETE/*_CHILD*/, SC_AC_OP_CREATE_EF, SC_AC_OP_CREATE_DF, SC_AC_OP_INVALIDATE, SC_AC_OP_REHABILITATE, SC_AC_OP_LOCK, SC_AC_OP_DELETE_SELF ];
    let ops_ef_chv = [ SC_AC_OP_READ,             SC_AC_OP_UPDATE,    0xFF,               SC_AC_OP_INVALIDATE, SC_AC_OP_REHABILITATE, SC_AC_OP_LOCK, SC_AC_OP_DELETE_SELF ];
    let ops_key    = [ SC_AC_OP_READ,             SC_AC_OP_UPDATE,    SC_AC_OP_CRYPTO,    SC_AC_OP_INVALIDATE, SC_AC_OP_REHABILITATE, SC_AC_OP_LOCK, SC_AC_OP_DELETE_SELF ];
    let ops_se     = [ SC_AC_OP_READ,             SC_AC_OP_UPDATE,    SC_AC_OP_CRYPTO,    SC_AC_OP_INVALIDATE, SC_AC_OP_REHABILITATE, SC_AC_OP_LOCK, SC_AC_OP_DELETE_SELF ];

    for idx_scb8 in 0..7 {
        let op =
            if       is_DFMF(fdb)                                         { ops_df_mf [idx_scb8] }
            else if  fdb == FDB_SE_FILE                                   { ops_se    [idx_scb8] }
            else if  fdb == FDB_RSA_KEY_EF || fdb == FDB_SYMMETRIC_KEY_EF { ops_key   [idx_scb8] }
            else                                                          { ops_ef_chv[idx_scb8] };
        se_file_add_acl_entry(card, file, scb8[idx_scb8], op);
    }

    let mut dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
    let file_id = file.id as u16;
//println!("file_id: {:X}", file_id);
    assert!(dp.files.contains_key(&file_id));
    /*if dp.files.contains_key(&file_id)*/
    let dp_files_value = dp.files.get_mut(&file_id).unwrap();
    if  dp_files_value.1[2] == 0 && dp_files_value.1[3] == 0 { // assume dp_files_value.1 wasn't provided by list_files, i.e. insert by acos5_create_file
        dp_files_value.1[0] = fdb;
//      dp_files_value.1[1] = dcb;
        unsafe { copy_nonoverlapping((file.id as u16).to_be_bytes().as_ptr(), dp_files_value.1.as_mut_ptr().add(2), 2); }
        if  file.type_!= SC_FILE_TYPE_DF && file.ef_structure != SC_FILE_EF_TRANSPARENT {
            dp_files_value.1[4] = unsafe { *ptr_bytes_tag_fcp_type.offset(3) };
            dp_files_value.1[5] = unsafe { *ptr_bytes_tag_fcp_type.add(len_bytes_tag_fcp_type-1) };
        }
        else {
            unsafe { copy_nonoverlapping((file.size as u16).to_be_bytes().as_ptr(), dp_files_value.1.as_mut_ptr().add(4), 2); }
        }
//      dp_files_value.1[6] = sfi;
//      dp_files_value.1[7] = lcsi;
    }
    if  dp_files_value.2.is_none() {
        dp_files_value.2  = Some(scb8);
    }
    if  dp_files_value.1[0] == FDB_RSA_KEY_EF && dp_files_value.1[6] == 0xFF {
        /* a better, more sophisticated distinction requires more info. Here, readable or not. Possibly read first byte from file */
        dp_files_value.1[6] = if scb8[0] != 0xFF {PKCS15_FILE_TYPE_RSAPUBLICKEY} else {PKCS15_FILE_TYPE_RSAPRIVATEKEY};
    }
        /*
                    if rbuf[0]==FDB_RSA_KEY_EF && dp.files[&file_id].2.is_some() && dp.files[&file_id].2.unwrap()[0]==0 {
                        if let Some(x) = dp.files.get_mut(&file_id) {
                            (*x).1[6] = PKCS15_FILE_TYPE_RSAPUBLICKEY;
                        }
                    }
        */
    /* if dp_files_value.1[0] == FDB_MF && dp_files_value.1[4..] == [0u8, 0, 0xFF, 0xFF] */  // correct the initially unknown/incorrect lcsi setting
    dp_files_value.1[7] = lcsi;
    if is_DFMF(fdb) {
        if  dp_files_value.1[4..6] == [0_u8; 2] {
            unsafe { copy_nonoverlapping(sefile_id.as_ptr(), dp_files_value.1.as_mut_ptr().add(4), 2); }
        }

        if  dp_files_value.4.is_none() && !vec_bytes_tag_fcp_sae.is_empty() {
//            println!("file_id: {:X}, vec_bytes_tag_fcp_sae: {:X?}", file_id, vec_bytes_tag_fcp_sae);
//            let y = (&mut dp_files_value.3).as_mut();
            let y = &mut dp_files_value.3;
            dp_files_value.4 = match se_parse_sae(y, vec_bytes_tag_fcp_sae.as_slice()) {
                Ok(val) => Some(val),
                Err(e) => { card.drv_data = Box::into_raw(dp) as *mut c_void; return e},
            }
        }
    }

    card.drv_data = Box::into_raw(dp) as *mut c_void;

    SC_SUCCESS
}


// assembles the byte string/data part for file creation via command "Create File"
// TODO special treatment for DF/MF is missing: optional ISO7816_RFU_TAG_FCP_SAE
// ATTENTION : expects from file.type the fdb , but NOT what usually is in file.type like e.g. SC_FILE_TYPE_WORKING_EF
//#[allow(dead_code)]
extern "C" fn acos5_construct_fci(card_ptr: *mut sc_card, file_ref_ptr: *const sc_file,
                                  out_ptr: *mut c_uchar, outlen_ptr: *mut usize) -> c_int
{
/* file 5032 created by OpenSC  pkcs15-init  --create-pkcs15 --so-pin 87654321
30 56 02 01 00 04 06 30 AB 40 68 81 C7 0C 23 68 74 74 70 73 3A 2F 2F 67 69 74 68 75 62 2E 63 6F 6D 2F 63 61 72 62 6C 75 65 2F 61 63 6F 73 35 5F
36 34 80 0D 41 43 4F 53 35 2D 36 34 20 43 61 72 64 03 02 04 10 A5 11 18 0F 32 30 31 39 30 39 30 31 31 38 30 37 34 37 5A 00 00 00 00

SEQUENCE (6 elem)
  INTEGER 0
  OCTET STRING (6 byte) 30AB406881C7
  UTF8String https://github.com/carblue/acos5_64
  [0] ACOS5-64 Card
  BIT STRING (4 bit) 0001
  [5] (1 elem)
    GeneralizedTime 2019-09-01 18:07:47 UTC


6F 16  83 02 2F 00   82 02 01 00  80 02 00 21  8C 08 7F 01 FF 01 01 FF 01 00
6F 30  83 02 41 00 88 01 00 8A 01 05 82 02 38 00 8D 02 41 03 84 10 41 43 4F 53 50 4B 43 53 2D 31 35 76 31 2E 30 30 8C 08 7F 03 FF 00 01 01 01 01 AB 00

6F 16  83 02 41 01   82 06 0A 00 00 15 00 01   8C 08 7F 03 FF 00 FF FF 01 FF
6F 16  83 02 41 02   82 06 0C 00 00 25 00 0C   8C 08 7F 03 FF 00 FF 01 01 FF
6F 16  83 02 41 03   82 06 1C 00 00 38 00 08   8C 08 7F 03 FF 00 FF 00 03 00

6F 16  83 02 50 31   82 02 01 00  80 02 00 6C  8C 08 7F 03 FF 00 03 FF 00 00
6F 16  83 02 41 11   82 02 01 00  80 02 00 80  8C 08 7F 03 FF 00 03 FF 00 00
6F 16  83 02 41 20   82 02 01 00  80 02 06 80  8C 08 7F 01 FF 00 01 FF 01 00

6F 16  83 02 41 31   82 02 09 00  80 02 02 15  8C 08 7F 01 FF 00 01 00 01 00
6F 16  83 02 41 F1   82 02 09 00  80 02 05 05  8C 08 7F 01 FF 00 01 01 01 FF
*/
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || file_ref_ptr.is_null() || out_ptr.is_null() ||
        outlen_ptr.is_null() {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let outlen = unsafe { &mut *outlen_ptr };
    if *outlen < 2 {
        return SC_ERROR_BUFFER_TOO_SMALL;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let file_ref = unsafe { &*file_ref_ptr };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun   = CStr::from_bytes_with_nul(b"acos5_construct_fci\0").unwrap();
    if cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(CALLED).unwrap());

//        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(CALLED).unwrap());

        wr_do_log_tu(card_ctx, f_log, line!(), fun, file_ref.path.len, unsafe{sc_dump_hex(file_ref.path.value.as_ptr(), file_ref.path.len)},
                     CStr::from_bytes_with_nul(b"path: %zu, %s\0").unwrap());

        wr_do_log_tu(card_ctx, f_log, line!(), fun, file_ref.namelen, unsafe{sc_dump_hex(file_ref.name.as_ptr(), file_ref.namelen)},
                     CStr::from_bytes_with_nul(b"name: %zu, %s\0").unwrap());

        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.type_, CStr::from_bytes_with_nul(b"type_: %u\0").unwrap());

        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.id, CStr::from_bytes_with_nul(b"id: 0x%X\0").unwrap());

        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.size, CStr::from_bytes_with_nul(b"size: %zu\0").unwrap());

        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.ef_structure, CStr::from_bytes_with_nul(b"ef_structure: %u\0").unwrap());
//        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.status, CStr::from_bytes_with_nul(b"status: %u\0").unwrap());
//        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.shareable, CStr::from_bytes_with_nul(b"shareable: %u\0").unwrap());
//        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.sid, CStr::from_bytes_with_nul(b"sid: %d\0").unwrap());
//        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.prop_attr_len, CStr::from_bytes_with_nul(b"prop_attr_len: %zu\0").unwrap());
/* * /
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[ 0], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_SELECT]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[ 1], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_LOCK]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[ 2], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_DELETE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[ 3], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_CREATE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[ 4], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_REHABILITATE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[ 5], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_INVALIDATE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[ 6], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_LIST_FILES]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[ 7], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_CRYPTO]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[ 8], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_DELETE_SELF]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[ 9], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_PSO_DECRYPT]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[10], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_PSO_ENCRYPT]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[11], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_PSO_COMPUTE_SIGNATURE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[12], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_PSO_VERIFY_SIGNATURE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[13], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_PSO_COMPUTE_CHECKSUM]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[14], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_PSO_VERIFY_CHECKSUM]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[15], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_INTERNAL_AUTHENTICATE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[16], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_EXTERNAL_AUTHENTICATE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[17], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_PIN_DEFINE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[18], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_PIN_CHANGE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[19], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_PIN_RESET]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[20], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_ACTIVATE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[21], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_DEACTIVATE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[22], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_READ]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[23], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_UPDATE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[24], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_WRITE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[25], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_RESIZE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[26], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_GENERATE]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[27], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_CREATE_EF]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[28], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_CREATE_DF]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[29], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_ADMIN]: %p\0").unwrap());
        wr_do_log_t(card_ctx, f_log, line!(), fun, file_ref.acl[30], CStr::from_bytes_with_nul(b"acl[SC_AC_OP_PIN_USE]: %p\0").unwrap());
/ * */
    }
    /* file type in profile to be entered aus FDB: File Descriptor Byte */
    let acl_category = match file_ref.type_ as u8 {
        FDB_DF | FDB_MF => ACL_CATEGORY_DF_MF,
        FDB_TRANSPARENT_EF |
        FDB_LINEAR_FIXED_EF |
        FDB_LINEAR_VARIABLE_EF |
        FDB_CYCLIC_EF |
        FDB_CHV_EF => ACL_CATEGORY_EF_CHV,
        FDB_RSA_KEY_EF |
        FDB_ECC_KEY_EF |
        FDB_SYMMETRIC_KEY_EF => ACL_CATEGORY_KEY,
        FDB_SE_FILE=> ACL_CATEGORY_SE,
        _  => {
println!("Non-match in let acl_category. file_ref.type_: {}", file_ref.type_);
            return -1
        }, // this includes FDB_PURSE_EF: unknown acl_category
    };

    let bytes_tag_fcp_sac = match convert_acl_array_to_bytes_tag_fcp_sac(&file_ref.acl, acl_category) {
        Ok(val) => val,
        Err(e) => return e,
    };
//println!("bytes_tag_fcp_sac: {:X?}", bytes_tag_fcp_sac); // bytes_tag_fcp_sac: [7F, 1, FF, 1, 1, 1, 1, 1]
    let mut buf2 = [0; 2];
    let mut ptr_diff_sum : usize = 0; // difference/distance of p and out   #![feature(ptr_offset_from)]
    let mut p = out_ptr;
    unsafe { *p = ISO7816_TAG_FCP }; // *p++ = 0x6F;  p++;
    p = unsafe { p.add(2) };
    ptr_diff_sum += 2;

    /* 4 bytes will be written for tag ISO7816_TAG_FCP_FID (0x83)  MANDATORY */
    unsafe { copy_nonoverlapping((file_ref.id as u16).to_be_bytes().as_ptr(), buf2.as_mut_ptr(), 2); }
    unsafe { sc_asn1_put_tag(u32::from(ISO7816_TAG_FCP_FID), buf2.as_ptr(), 2, p, *outlen-ptr_diff_sum, &mut p) };
    ptr_diff_sum += 4;

    /* 1 or 5 bytes will be written for tag ISO7816_TAG_FCP_TYPE (0x82) MANDATORY */
    //  e.g.  {82 06} 0A 00 00 15 00 01
    let fdb = file_ref.type_ as u8;
    if [FDB_LINEAR_FIXED_EF, FDB_LINEAR_VARIABLE_EF, FDB_CYCLIC_EF, FDB_CHV_EF, FDB_SYMMETRIC_KEY_EF, FDB_PURSE_EF, FDB_SE_FILE].contains(&fdb) &&
        (file_ref.record_length==0 || file_ref.record_count==0) { return SC_ERROR_INVALID_ARGUMENTS; }
    if [FDB_LINEAR_FIXED_EF, FDB_LINEAR_VARIABLE_EF, FDB_CYCLIC_EF, FDB_CHV_EF, FDB_SYMMETRIC_KEY_EF, FDB_PURSE_EF, FDB_SE_FILE].contains(&fdb) {
        let mut rec_buf = [0; 5];
//        05h    FDB+DCB+00h+MRL+NOR
        rec_buf[0] = fdb;
        rec_buf[3] = file_ref.record_length as u8;
        rec_buf[4] = file_ref.record_count  as u8;
        unsafe { sc_asn1_put_tag(u32::from(ISO7816_TAG_FCP_TYPE), rec_buf.as_ptr(), 5, p, *outlen-ptr_diff_sum, &mut p) };
        ptr_diff_sum += 7;
    }
    else {
        buf2[0] = fdb;
        buf2[1] = 0;
        unsafe { sc_asn1_put_tag(u32::from(ISO7816_TAG_FCP_TYPE), buf2.as_ptr(), 2, p, *outlen-ptr_diff_sum, &mut p) };
        ptr_diff_sum += 4;
    }

    /* 3 bytes will be written for tag ISO7816_TAG_FCP_LCS (0x8A) */
    buf2[0] = 1; // skip cos5 command "Activate File" and create as activated
    unsafe { sc_asn1_put_tag(u32::from(ISO7816_TAG_FCP_LCS), buf2.as_ptr(), 1, p, *outlen-ptr_diff_sum, &mut p) };
    ptr_diff_sum += 3;

    if [FDB_TRANSPARENT_EF, FDB_RSA_KEY_EF, FDB_ECC_KEY_EF].contains(&fdb) { // any non-record-based, non-DF/MF fdb
        /* 4 bytes will be written for tag ISO7816_TAG_FCP_SIZE (0x80) */
        assert!(file_ref.size > 0);
        unsafe { copy_nonoverlapping((file_ref.size as u16).to_be_bytes().as_ptr(), buf2.as_mut_ptr(), 2); }
        unsafe { sc_asn1_put_tag(u32::from(ISO7816_TAG_FCP_SIZE), buf2.as_ptr(), 2, p, *outlen-ptr_diff_sum, &mut p) };
        ptr_diff_sum += 4;
    }

    /*  bytes will be written for tag ISO7816_RFU_TAG_FCP_SAC (0x8C) MANDATORY */
    unsafe { sc_asn1_put_tag(u32::from(ISO7816_RFU_TAG_FCP_SAC), bytes_tag_fcp_sac.as_ptr(), bytes_tag_fcp_sac.len(),
                             p, *outlen-ptr_diff_sum, &mut p) };
    ptr_diff_sum += 2+bytes_tag_fcp_sac.len();

    if is_DFMF(fdb) {
        /* 4 bytes will be written for tag ISO7816_RFU_TAG_FCP_SEID (0x8D) */
        unsafe { copy_nonoverlapping(((file_ref.id+3) as u16).to_be_bytes().as_ptr(), buf2.as_mut_ptr(), 2); }
        unsafe { sc_asn1_put_tag(u32::from(ISO7816_RFU_TAG_FCP_SEID), buf2.as_ptr(), 2, p, *outlen-ptr_diff_sum, &mut p) };
        ptr_diff_sum += 4;

        if file_ref.namelen>0 {
            /* bytes will be written for tag ISO7816_TAG_FCP_DF_NAME (0x84) */
            unsafe { sc_asn1_put_tag(u32::from(ISO7816_TAG_FCP_DF_NAME), file_ref.name.as_ptr(), file_ref.namelen, p, *outlen-ptr_diff_sum, &mut p) };
            ptr_diff_sum += 2+file_ref.namelen;
        }
        //ISO7816_RFU_TAG_FCP_SAE
    }

    unsafe { *out_ptr.add(1) = (ptr_diff_sum-2) as c_uchar; };
    *outlen = ptr_diff_sum;

    if cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(RETURNING).unwrap());
    }
    SC_SUCCESS
}

/*
 * What it does
 * @apiNote
 * @param
 * @return
 */
#[cfg_attr(feature = "cargo-clippy", allow(clippy::if_same_then_else))]
extern "C" fn acos5_pin_cmd(card_ptr: *mut sc_card, data_ptr: *mut sc_pin_cmd_data, tries_left_ptr: *mut c_int) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || data_ptr.is_null() {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let pin_cmd_data = unsafe { &mut *data_ptr };
    let mut dummy_tries_left : c_int = -1;

    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun   = CStr::from_bytes_with_nul(b"acos5_pin_cmd\0").unwrap();
    let fmt   = CStr::from_bytes_with_nul(b"called for cmd: %d\0").unwrap();
    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(), fun, pin_cmd_data.cmd, fmt);
    }

/*
    if      SC_PIN_CMD_GET_INFO == pin_cmd_data.cmd {
         pin_get_policy(card, pin_cmd_data,
                       if tries_left_ptr.is_null() {
                                    &mut dummy_tries_left
                                }
                                else {
                                    unsafe { &mut *tries_left_ptr }
                                }
        )
    }
*/
    if      SC_PIN_CMD_GET_INFO == pin_cmd_data.cmd { // pin1 unused, pin2 unused
/*
println!("SC_PIN_CMD_GET_INFO: before execution:");
println!("pin_cmd_data.cmd:           {:X}", pin_cmd_data.cmd);
println!("pin_cmd_data.flags:         {:X}", pin_cmd_data.flags);
println!("pin_cmd_data.pin_type:      {:X}", pin_cmd_data.pin_type);
println!("pin_cmd_data.pin_reference: {:X}", pin_cmd_data.pin_reference);

println!("pin_cmd_data.apdu:          {:p}", pin_cmd_data.apdu);
println!("pin_cmd_data.pin2.len:      {}", pin_cmd_data.pin2.len);
println!();
println!("pin_cmd_data.pin1.prompt:   {:p}", pin_cmd_data.pin1.prompt);
println!("pin_cmd_data.pin1.data:     {:p}", pin_cmd_data.pin1.data);
println!("pin_cmd_data.pin1.len:      {}", pin_cmd_data.pin1.len);
if ! pin_cmd_data.pin1.data.is_null() {
    println!("pin_cmd_data.pin1           {:X?}", unsafe { from_raw_parts(pin_cmd_data.pin1.data, pin_cmd_data.pin1.len as usize) } );
}
println!("pin_cmd_data.pin1.min_length:      {}", pin_cmd_data.pin1.min_length);
println!("pin_cmd_data.pin1.max_length:      {}", pin_cmd_data.pin1.max_length);
println!("pin_cmd_data.pin1.stored_length:   {}", pin_cmd_data.pin1.stored_length);

println!("pin_cmd_data.pin1.encoding:        {:X}", pin_cmd_data.pin1.encoding);
println!("pin_cmd_data.pin1.pad_length:      {}", pin_cmd_data.pin1.pad_length);
println!("pin_cmd_data.pin1.pad_char:        {}", pin_cmd_data.pin1.pad_char);

println!("pin_cmd_data.pin1.offset:          {}", pin_cmd_data.pin1.offset);
println!("pin_cmd_data.pin1.length_offset:   {}", pin_cmd_data.pin1.length_offset);

println!("pin_cmd_data.pin1.max_tries:   {}", pin_cmd_data.pin1.max_tries);
println!("pin_cmd_data.pin1.tries_left:  {}", pin_cmd_data.pin1.tries_left);
println!("pin_cmd_data.pin1.logged_in:   {}", pin_cmd_data.pin1.logged_in);
//println!("pin_cmd_data.pin1.acls:        {:?}", pin_cmd_data.pin1.acls);
println!();
*/

        if card.type_ == SC_CARD_TYPE_ACOS5_64_V2 {
//            let rv = unsafe { (*(*sc_get_iso7816_driver()).ops).pin_cmd.unwrap()(card, pin_cmd_data, tries_left_ptr) } ;
            let rv = pin_get_policy(card, pin_cmd_data,
                           if tries_left_ptr.is_null() {
                               &mut dummy_tries_left
                           }
                           else {
                               unsafe { &mut *tries_left_ptr }
                           }
            );
/*
println!("SC_PIN_CMD_GET_INFO: after execution:");
println!("pin_cmd_data.pin1.offset:          {}", pin_cmd_data.pin1.offset);
println!("pin_cmd_data.pin1.length_offset:   {}", pin_cmd_data.pin1.length_offset);
println!("pin_cmd_data.pin1.max_tries:   {}", pin_cmd_data.pin1.max_tries);
println!("pin_cmd_data.pin1.tries_left:  {}", pin_cmd_data.pin1.tries_left);
println!("pin_cmd_data.pin1.logged_in:   {}", pin_cmd_data.pin1.logged_in);
println!();
*/
            rv
        }
        else {
            let file_id = file_id_from_cache_current_path(card);
//println!("file_id: {:X}", file_id);
            let scb_verify = se_get_sae_scb(card, &[0_u8, 0x20, 0, pin_cmd_data.pin_reference as u8][..]);
//println!("scb_verify: {:X}", scb_verify);

            if scb_verify == 0xFF {
                wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(
                    b"SC_PIN_CMD_GET_INFO won't be done: It's not allowed by SAE\0").unwrap());
                SC_ERROR_SECURITY_STATUS_NOT_SATISFIED
            }
            else if (scb_verify & 0x40) == 0x40  &&  SC_AC_CHV == pin_cmd_data.pin_type {
                let res_se_sm = se_get_is_scb_suitable_for_sm_has_ct(card, file_id, scb_verify & 0x1F);
//println!("res_se_sm: {:?}", res_se_sm);
                if !res_se_sm.0 {
                    wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(
                        b"SC_PIN_CMD_GET_INFO won't be done: It's SM protected, but the CRT template(s) don't accomplish requirements\0").unwrap());
                    SC_ERROR_SECURITY_STATUS_NOT_SATISFIED
                }
                else {
                    let rv = sm_pin_cmd_get_policy(card, pin_cmd_data, if tries_left_ptr.is_null() { &mut dummy_tries_left }
                        else { unsafe { &mut *tries_left_ptr } });
/*
println!("SC_PIN_CMD_GET_INFO: after execution:");
println!("pin_cmd_data.pin1.offset:          {}", pin_cmd_data.pin1.offset);
println!("pin_cmd_data.pin1.length_offset:   {}", pin_cmd_data.pin1.length_offset);
println!("pin_cmd_data.pin1.max_tries:   {}", pin_cmd_data.pin1.max_tries);
println!("pin_cmd_data.pin1.tries_left:  {}", pin_cmd_data.pin1.tries_left);
println!("pin_cmd_data.pin1.logged_in:   {}", pin_cmd_data.pin1.logged_in);
println!();
*/
                    rv
                }
            }
            else {
                pin_get_policy(card, pin_cmd_data,
                                        if tries_left_ptr.is_null() {
                                            &mut dummy_tries_left
                                        }
                                        else {
                                            unsafe { &mut *tries_left_ptr }
                                        }
                )
            }
        }
    }
    else if SC_PIN_CMD_VERIFY   == pin_cmd_data.cmd { // pin1 is used, pin2 unused
        if pin_cmd_data.pin1.len <= 0 || pin_cmd_data.pin1.data.is_null() {
            return -1;
        }
/*
        println!("SC_PIN_CMD_VERIFY: before execution:");
        println!("pin_cmd_data.cmd:           {:X}", pin_cmd_data.cmd);
        println!("pin_cmd_data.flags:         {:X}", pin_cmd_data.flags);
        println!("pin_cmd_data.pin_type:      {:X}", pin_cmd_data.pin_type);
        println!("pin_cmd_data.pin_reference: {:X}", pin_cmd_data.pin_reference);

        println!("pin_cmd_data.apdu:          {:p}", pin_cmd_data.apdu);
        println!("pin_cmd_data.pin2.len:      {}", pin_cmd_data.pin2.len);
        println!();
        println!("pin_cmd_data.pin1.prompt:   {:p}", pin_cmd_data.pin1.prompt);
        println!("pin_cmd_data.pin1.data:     {:p}", pin_cmd_data.pin1.data);
        println!("pin_cmd_data.pin1.len:      {}", pin_cmd_data.pin1.len);
        if ! pin_cmd_data.pin1.data.is_null() {
            println!("pin_cmd_data.pin1           {:X?}", unsafe { from_raw_parts(pin_cmd_data.pin1.data, pin_cmd_data.pin1.len as usize) } );
        }
        println!("pin_cmd_data.pin1.min_length:      {}", pin_cmd_data.pin1.min_length);
        println!("pin_cmd_data.pin1.max_length:      {}", pin_cmd_data.pin1.max_length);
        println!("pin_cmd_data.pin1.stored_length:   {}", pin_cmd_data.pin1.stored_length);

        println!("pin_cmd_data.pin1.encoding:        {:X}", pin_cmd_data.pin1.encoding);
        println!("pin_cmd_data.pin1.pad_length:      {}", pin_cmd_data.pin1.pad_length);
        println!("pin_cmd_data.pin1.pad_char:        {}", pin_cmd_data.pin1.pad_char);

        println!("pin_cmd_data.pin1.offset:          {}", pin_cmd_data.pin1.offset);
        println!("pin_cmd_data.pin1.length_offset:   {}", pin_cmd_data.pin1.length_offset);

        println!("pin_cmd_data.pin1.max_tries:   {}", pin_cmd_data.pin1.max_tries);
        println!("pin_cmd_data.pin1.tries_left:  {}", pin_cmd_data.pin1.tries_left);
        println!("pin_cmd_data.pin1.logged_in:   {}", pin_cmd_data.pin1.logged_in);
//        println!("pin_cmd_data.pin1.acls:        {:?}", pin_cmd_data.pin1.acls);
        println!();
*/
/*
SC_PIN_CMD_VERIFY: before execution:
pin_cmd_data.cmd:           0
pin_cmd_data.flags:         2
pin_cmd_data.pin_type:      1
pin_cmd_data.pin_reference: 81
pin_cmd_data.apdu:          0x0
pin_cmd_data.pin2.len:      0

pin_cmd_data.pin1.prompt:   0x0
pin_cmd_data.pin1.data:     0x5558bdf12cc0
pin_cmd_data.pin1.len:      8
pin_cmd_data.pin1           [31, 32, 33, 34, 35, 36, 37, 38]
pin_cmd_data.pin1.min_length:      4
pin_cmd_data.pin1.max_length:      8
pin_cmd_data.pin1.stored_length:   0
pin_cmd_data.pin1.encoding:        0
pin_cmd_data.pin1.pad_length:      8
pin_cmd_data.pin1.pad_char:        255
pin_cmd_data.pin1.offset:          0  -> 5
pin_cmd_data.pin1.length_offset:   0
pin_cmd_data.pin1.max_tries:   0
pin_cmd_data.pin1.tries_left:  0      -> -1
pin_cmd_data.pin1.logged_in:   0      -> 1

SC_PIN_CMD_VERIFY: after execution:
pin_cmd_data.pin1.offset:          5
pin_cmd_data.pin1.length_offset:   0
pin_cmd_data.pin1.max_tries:   0
pin_cmd_data.pin1.tries_left:  -1
pin_cmd_data.pin1.logged_in:   1
*/

        if card.type_ == SC_CARD_TYPE_ACOS5_64_V2 {
            let rv = unsafe { (*(*sc_get_iso7816_driver()).ops).pin_cmd.unwrap()(card, pin_cmd_data, tries_left_ptr) } ;
/*
println!("SC_PIN_CMD_VERIFY: after execution:");
println!("pin_cmd_data.pin1.offset:          {}", pin_cmd_data.pin1.offset);
println!("pin_cmd_data.pin1.length_offset:   {}", pin_cmd_data.pin1.length_offset);
println!("pin_cmd_data.pin1.max_tries:   {}", pin_cmd_data.pin1.max_tries);
println!("pin_cmd_data.pin1.tries_left:  {}", pin_cmd_data.pin1.tries_left);
println!("pin_cmd_data.pin1.logged_in:   {}", pin_cmd_data.pin1.logged_in);
println!();
*/
            rv
        }
        else {
            let file_id = file_id_from_cache_current_path(card);
//println!("file_id: {:X}", file_id);
            let scb_verify = se_get_sae_scb(card, &[0_u8, 0x20, 0, pin_cmd_data.pin_reference as u8][..]);
//println!("scb_verify: {:X}", scb_verify);

            if scb_verify == 0xFF {
                wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(
                    b"SC_PIN_CMD_VERIFY won't be done: It's not allowed by SAE\0").unwrap());
                SC_ERROR_SECURITY_STATUS_NOT_SATISFIED
            }
            else if (scb_verify & 0x40) == 0x40  &&  SC_AC_CHV == pin_cmd_data.pin_type {
                let res_se_sm = se_get_is_scb_suitable_for_sm_has_ct(card, file_id, scb_verify & 0x1F);
//println!("res_se_sm: {:?}", res_se_sm);
                // TODO think about whether SM mode Confidentiality should be enforced
                if !res_se_sm.0 {
                    wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(
                        b"SC_PIN_CMD_VERIFY won't be done: It's SM protected, but the CRT template(s) don't accomplish requirements\0").unwrap());
                    SC_ERROR_SECURITY_STATUS_NOT_SATISFIED
                }
                else {
                    let rv = sm_pin_cmd_verify(card, pin_cmd_data, if tries_left_ptr.is_null() { &mut dummy_tries_left }
                        else { unsafe { &mut *tries_left_ptr } }, res_se_sm.1);
/*
println!("SC_PIN_CMD_VERIFY: after execution:");
println!("pin_cmd_data.pin1.offset:          {}", pin_cmd_data.pin1.offset);
println!("pin_cmd_data.pin1.length_offset:   {}", pin_cmd_data.pin1.length_offset);
println!("pin_cmd_data.pin1.max_tries:   {}", pin_cmd_data.pin1.max_tries);
println!("pin_cmd_data.pin1.tries_left:  {}", pin_cmd_data.pin1.tries_left);
println!("pin_cmd_data.pin1.logged_in:   {}", pin_cmd_data.pin1.logged_in);
println!();
*/
                    rv
                }
            }
            else {
                unsafe { (*(*sc_get_iso7816_driver()).ops).pin_cmd.unwrap()(card, pin_cmd_data, tries_left_ptr) }
            }
        }
    }
    else if SC_PIN_CMD_CHANGE   == pin_cmd_data.cmd { // pin1 is old pin, pin2 is new pin
//        let pindata_rm = unsafe {&mut *data_ptr};
//        println!("sc_pin_cmd_data:  flags: {:X}, pin_type: {:X}, pin_reference: {:X}, apdu: {:?}", pindata_rm.flags, pindata_rm.pin_type, pindata_rm.pin_reference, pindata_rm.apdu);
//        println!("sc_pin_cmd_pin 1: len: {}, [{:X},{:X},{:X},{:X}]", pindata_rm.pin1.len, unsafe{*pindata_rm.pin1.data.add(0)}, unsafe{*pindata_rm.pin1.data.add(1)}, unsafe{*pindata_rm.pin1.data.add(2)}, unsafe{*pindata_rm.pin1.data.add(3)});
//        println!("sc_pin_cmd_pin 2: len: {}, [{:X},{:X},{:X},{:X}]", pindata_rm.pin2.len, unsafe{*pindata_rm.pin2.data.add(0)}, unsafe{*pindata_rm.pin2.data.add(1)}, unsafe{*pindata_rm.pin2.data.add(2)}, unsafe{*pindata_rm.pin2.data.add(3)});
        unsafe { (*(*sc_get_iso7816_driver()).ops).pin_cmd.unwrap()(card, pin_cmd_data, tries_left_ptr) }
    }
    else if SC_PIN_CMD_UNBLOCK  == pin_cmd_data.cmd { // pin1 is PUK, pin2 is new pin for the one blocked
        unsafe { (*(*sc_get_iso7816_driver()).ops).pin_cmd.unwrap()(card, pin_cmd_data, tries_left_ptr) }
    }
    else {
        SC_ERROR_NO_CARD_SUPPORT
/*
        unsafe {
            if !tries_left_ptr.is_null() /* || pin_cmd_data.cmd == SC_PIN_CMD_GET_INFO */ {
                println!("tries_left_ptr: {}", *tries_left_ptr);
            }
            /* */

            if !pin_cmd_data.pin1.data.is_null() {
                let mut arr_pin = [0; 8];
                for i in 0..pin_cmd_data.pin1.len as usize {
                    arr_pin[i] = *pin_cmd_data.pin1.data.add(i);
                }
                println!("pin1.data: {:?}, pin_cmd_data: {:?}", arr_pin, *pin_cmd_data); // , *pin_cmd_data.apdu
            }
            else {
                println!("pin_cmd_data: {:?}", *pin_cmd_data);
            }

            /*       */
        }

        let rv = unsafe { (*(*sc_get_iso7816_driver()).ops).pin_cmd.unwrap()(card, data, tries_left_ptr) };
        if rv != SC_SUCCESS {
            return rv;
        }
*/
    }
}


/*
 * What it does
 * @apiNote
 * @param
 * @return
 */
/// Reads an RSA or EC public key file and outputs formatted as DER
///
/// @param  card       INOUT
/// @param  algorithm  IN     Number of bytes available in buf from position buf onwards\
/// @param  key_path   OUT    Receiving address for: Class\
/// @param  tag_out  OUT    Receiving address for: Tag\
/// @param  taglen   OUT    Receiving address for: Number of bytes available in V\
/// @return          SC_SUCCESS or error code\
/// On error, buf may have been set to NULL, and (except on SC_ERROR_ASN1_END_OF_CONTENTS) no OUT param get's set\
/// OUT tag_out and taglen are guaranteed to have values set on SC_SUCCESS (cla_out only, if also (buf[0] != 0xff && buf[0] != 0))\

extern "C" fn acos5_read_public_key(card_ptr: *mut sc_card, algorithm: c_uint, key_path_ptr: *mut sc_path,
     key_reference: c_uint, modulus_length: c_uint, out: *mut *mut c_uchar, out_len: *mut usize) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || key_path_ptr.is_null() {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
//    let key_path_ref : &sc_path = unsafe { &*key_path_ptr };

    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun     = CStr::from_bytes_with_nul(b"acos5_read_public_key\0").unwrap();
    let fmt   = CStr::from_bytes_with_nul(CALLED).unwrap();
    let fmt_1 = CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap();
//  let fmt_2 = CStr::from_bytes_with_nul(RETURNING_INT).unwrap();
    if cfg!(log) {
        wr_do_log(card_ctx, f_log, line!(), fun, fmt);
    }

    if algorithm != SC_ALGORITHM_RSA {
        let rv = SC_ERROR_NO_CARD_SUPPORT;
        if cfg!(log) {
            wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, fmt_1);
        }
        return rv;
    }
    assert!(modulus_length>=512 && modulus_length<=4096);
    let mlbyte : usize = (modulus_length as usize)/8; /* key modulus_length in byte (expected to be a multiple of 32)*/
    let le_total = mlbyte + 21;
    let fmt = CStr::from_bytes_with_nul(b"read public key(ref:%i; modulus_length:%i; modulus_bytes:%zu)\0").unwrap();
    if cfg!(log) {
        wr_do_log_tuv(card_ctx, f_log, line!(), fun, key_reference, modulus_length, mlbyte, fmt);
    }

    let mut file_out_ptr_mut = null_mut();
//    let mut rv = select_file_by_path(card_ref_mut, key_path_ref, &mut file_out_ptr_mut, true/*, true*/);
    let mut rv = /*acos5_select_file*/unsafe {sc_select_file(card, key_path_ptr, &mut file_out_ptr_mut)};
    if rv != SC_SUCCESS {
        if cfg!(log) {
            wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(b"failed to select public key file\0")
                      .unwrap());
        }
        return rv;
    }

    let mut rbuf = [0; RSAPUB_MAX_LEN];
    rv = unsafe { sc_read_binary(card, 0, rbuf.as_mut_ptr(), le_total, 0) };
    if rv < le_total as c_int {
        if cfg!(log) {
            wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(b"get key failed\0")
                .unwrap());
        }
        return rv;
    }
/* * /
    // TODO use instead : sc_read_binary
    /* retrieve the raw content of currently selected RSA pub file */
    let command = [0x80, 0xCA, 0x00, 0x00, 0xFF];
    let mut apdu = sc_apdu::default();
    rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
    assert_eq!(rv, SC_SUCCESS);
    assert_eq!(apdu.cse, SC_APDU_CASE_2_SHORT);

    let mut rbuf = [0; RSAPUB_MAX_LEN];
    let mut le_remaining = le_total;
    while le_remaining > 0 {
        let offset = le_total - le_remaining;
        apdu.le      =  if le_remaining > 0xFFusize {0xFFusize} else {le_remaining};
        apdu.resp    =  unsafe { rbuf.as_mut_ptr().add(offset) };
        apdu.resplen =  rbuf.len() - offset;
        apdu.p1      =  ((offset >> 8) & 0xFFusize) as u8;
        apdu.p2      =  ( offset       & 0xFFusize) as u8;
        rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
        rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
        if rv != SC_SUCCESS {
            if cfg!(log) {
                wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(b"get key failed\0")
                          .unwrap());
            }
            return rv;
        }
        assert_eq!(apdu.resplen, apdu.le);
        le_remaining -= apdu.le;
    }
*/
/* */
    /* check the raw content of RSA pub file
00 20 41 F1 03 00 00 00 00 00 00 00 00 00 00 00 . A.............
00 00 01 00 01 6A 54 EB 93 CD 31 9E 37 2D 59 74 .....jT...1.7-Yt
3F004100 41 31
     */
    if    rbuf[0] != 0
       || rbuf[1] != ((modulus_length+8)/128) as u8 /* encode_key_RSA_ModulusBitLen(modulus_length) */
//     || rbuf[2] != key_path_ref.value[key_path_ref.len-2] /* FIXME RSAKEYID_CONVENTION */
//     || rbuf[3] != ( (key_path_ref.value[key_path_ref.len-1] as u16 +0xC0u16)       & 0xFFu16) as  /* FIXME RSAKEYID_CONVENTION */
//     || rbuf[4] != 3 // the bit setting for ACOS5-EVO is not known exactly
    {
        if cfg!(log) {
            wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul
                      (b"### failed: check the raw content of RSA pub file: within the first 5 bytes there is content that indicates an invalid public key ###\0").unwrap());
        }
        return SC_ERROR_INCOMPATIBLE_KEY;
    }

    // skip leading zero bytes of exponent; usually only 3 of 16 bytes are used; otherwise pkcs15-tool.c:read_ssh_key doesn't work
    let mut view = &rbuf[5..21];
    while !view.is_empty() && view[0] == 0 {
        view = &view[1..];
    }
    let raw_exponent_len = view.len();
    assert!(raw_exponent_len>0 && raw_exponent_len<=16);
    let rsa_key = sc_pkcs15_pubkey_rsa {
        exponent: sc_pkcs15_bignum{ data: unsafe { rbuf.as_mut_ptr().add(21-raw_exponent_len) }, len: raw_exponent_len},
        modulus:  sc_pkcs15_bignum{ data: unsafe { rbuf.as_mut_ptr().add(21) }, len: mlbyte }
    };

    /* transform the raw content to der-encoded */
    if rsa_key.exponent.len > 0 && rsa_key.modulus.len > 0 {
        rv = unsafe { sc_pkcs15_encode_pubkey_rsa(card_ctx, &rsa_key, out, out_len) };
        if rv < 0 {
            if cfg!(log) {
                wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul
                             (b"sc_pkcs15_encode_pubkey_rsa failed: returning with: %d (%s)\n\0").unwrap());
            }
            return rv;
        }
    }
    else {
        rv = SC_ERROR_INTERNAL;
        if cfg!(log) {
            wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul
            (b"if rsa_key.exponent.len > 0 && rsa_key.modulus.len > 0  failure: returning with: %d (%s)\n\0").unwrap());
        }
        return SC_ERROR_INTERNAL;
    }
    SC_SUCCESS
}


//TODO temporarily allow cognitive_complexity
#[cfg_attr(feature = "cargo-clippy", allow(clippy::cognitive_complexity))]
extern "C" fn acos5_set_security_env(card_ptr: *mut sc_card, env_ref_ptr: *const sc_security_env, _se_num: c_int) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || env_ref_ptr.is_null() {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let env_ref  = unsafe { & *env_ref_ptr };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun   = CStr::from_bytes_with_nul(b"acos5_set_security_env\0").unwrap();
    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(), fun, env_ref.operation, CStr::from_bytes_with_nul(b"called  for operation %d\0").unwrap());
    }
//println!("set_security_env: *env_ref_ptr: sc_security_env: {:?}", *env_ref);
    set_sec_env(card, env_ref);
    let mut rv;

    if SC_SEC_OPERATION_DERIVE == env_ref.operation
//        || ( cfg!(not(any(v0_17_0, v0_18_0, v0_19_0))) && (SC_SEC_OPERATION_WRAP == env_ref.operation) )
    {
        rv = SC_ERROR_NO_CARD_SUPPORT;
        if cfg!(log) {
            wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
        }
        return rv;
    }

    else if (SC_SEC_OPERATION_GENERATE_RSAPRIVATE == env_ref.operation ||
             SC_SEC_OPERATION_GENERATE_RSAPUBLIC  == env_ref.operation)   &&
             (env_ref.flags & SC_SEC_ENV_FILE_REF_PRESENT) > 0 &&
             (env_ref.flags & SC_SEC_ENV_ALG_PRESENT) > 0 && env_ref.algorithm==SC_ALGORITHM_RSA
    {
        assert!(env_ref.file_ref.len >= 2);
        let path_idx = env_ref.file_ref.len - 2;
        let command = [0x00, 0x22, 0x01, 0xB6, 0x0A, 0x80, 0x01, 0x10, 0x81, 0x02,
            env_ref.file_ref.value[path_idx], env_ref.file_ref.value[path_idx+1],  0x95, 0x01,
            if SC_SEC_OPERATION_GENERATE_RSAPRIVATE == env_ref.operation {0x40} else {0x80}];
        let mut apdu = sc_apdu::default();
        rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
        assert_eq!(rv, SC_SUCCESS);
        assert_eq!(apdu.cse, SC_APDU_CASE_3_SHORT);
        rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
//    println!("rv: {}, apdu: {:?}", rv, apdu);
        rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
        if rv != SC_SUCCESS {
            if cfg!(log) {
                wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul
                    (b"Set Security Environment for Generate Key pair' failed\0").unwrap());
                wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) },
                             CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
            }
            return rv;
        }
    }

    else if SC_SEC_OPERATION_SIGN == env_ref.operation   &&
        env_ref.algorithm==SC_ALGORITHM_RSA && (env_ref.flags & SC_SEC_ENV_FILE_REF_PRESENT) > 0
    {
        // TODO where is the decision taken to use PKCS#1 scheme padding?
        let algo = if (env_ref.algorithm_flags & SC_ALGORITHM_RSA_PAD_ISO9796) == 0 {0x10_u8} else {0x11_u8};
        assert!(env_ref.file_ref.len >= 2);
        let path_idx = env_ref.file_ref.len - 2;
        if SC_SEC_OPERATION_SIGN == env_ref.operation {
            let command = [0x00, 0x22, 0x01, 0xB6, 0x0A, 0x80, 0x01, algo, 0x81, 0x02,  env_ref.file_ref.value[path_idx], env_ref.file_ref.value[path_idx+1],  0x95, 0x01, 0x40];
            let mut apdu = sc_apdu::default();
            rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
            assert_eq!(rv, SC_SUCCESS);
            assert_eq!(apdu.cse, SC_APDU_CASE_3_SHORT);
            rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
            rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
//    println!("rv: {}, apdu: {:?}", rv, apdu);
            if rv != SC_SUCCESS {
                rv = SC_ERROR_KEYPAD_MSG_TOO_LONG;
                if cfg!(log) {
                    wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul
                        (b"'Set SecEnv for Sign' failed\0").unwrap());
                    wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
                }
                return rv;
            }
        }
        /* sign may need decrypt (for non-SHA1/SHA256 hashes), thus prepare for a CT as well */
        let command = [0x00, 0x22, 0x01, 0xB8, 0x0A, 0x80, 0x01, 0x13, 0x81, 0x02,
            env_ref.file_ref.value[path_idx], env_ref.file_ref.value[path_idx+1],  0x95, 0x01, 0x40];
        let mut apdu = sc_apdu::default();
        rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
        assert_eq!(rv, SC_SUCCESS);
        assert_eq!(apdu.cse, SC_APDU_CASE_3_SHORT);
        rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
        rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
//    println!("rv: {}, apdu: {:?}", rv, apdu);
        if rv != SC_SUCCESS {
            rv = SC_ERROR_KEYPAD_MSG_TOO_LONG;
            if cfg!(log) {
                wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul
                    (b"'Set SecEnv for Decrypt' failed\0").unwrap());
                wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
            }
            return rv;
        }
    }
/**/
    else if (SC_SEC_OPERATION_DECIPHER            == env_ref.operation ||
             SC_SEC_OPERATION_DECIPHER_RSAPRIVATE == env_ref.operation
            )  &&  env_ref.algorithm==SC_ALGORITHM_RSA && (env_ref.flags & SC_SEC_ENV_FILE_REF_PRESENT) > 0
    {
        assert!(env_ref.file_ref.len >= 2);
        let path_idx = env_ref.file_ref.len - 2;
        let command = [0x00, 0x22, 0x01, 0xB8, 0x0A, 0x80, 0x01, 0x13, 0x81, 0x02,
            env_ref.file_ref.value[path_idx], env_ref.file_ref.value[path_idx+1],  0x95, 0x01, 0x40];
        let mut apdu = sc_apdu::default();
        rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
        assert_eq!(rv, SC_SUCCESS);
        assert_eq!(apdu.cse, SC_APDU_CASE_3_SHORT);
        rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
//    println!("rv: {}, apdu: {:?}", rv, apdu);
        rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
        if rv != SC_SUCCESS {
            rv = SC_ERROR_KEYPAD_MSG_TOO_LONG;
            if cfg!(log) {
                wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul
                    (b"'Set SecEnv for RSA Decrypt' failed\0").unwrap());
                wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
            }
            return rv;
        }
    }

    else if SC_SEC_OPERATION_ENCIPHER_RSAPUBLIC == env_ref.operation   &&
            env_ref.algorithm==SC_ALGORITHM_RSA && (env_ref.flags & SC_SEC_ENV_FILE_REF_PRESENT) > 0
    {
//        let algo = 0x12; // encrypt: 0x12, decrypt: 0x13
        assert!(env_ref.file_ref.len >= 2);
        let path_idx = env_ref.file_ref.len - 2;
        let command = [0x00, 0x22, 0x01, 0xB8, 0x0A, 0x80, 0x01, 0x12, 0x81, 0x02,
            env_ref.file_ref.value[path_idx], env_ref.file_ref.value[path_idx+1],  0x95, 0x01, 0x40];
        let mut apdu = sc_apdu::default();
        rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
        assert_eq!(rv, SC_SUCCESS);
        assert_eq!(apdu.cse, SC_APDU_CASE_3_SHORT);
        rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
        rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
//    println!("rv: {}, apdu: {:?}", rv, apdu);
        if rv != SC_SUCCESS {
            rv = SC_ERROR_KEYPAD_MSG_TOO_LONG;
            if cfg!(log) {
                wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul
                    (b"'Set SecEnv for encrypt_asym' failed\0").unwrap());
                wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
            }
            return rv;
        }
    }
    else if [SC_SEC_OPERATION_ENCIPHER_SYMMETRIC, SC_SEC_OPERATION_DECIPHER_SYMMETRIC].contains(&env_ref.operation)  &&
            (env_ref.flags & SC_SEC_ENV_KEY_REF_PRESENT) > 0 && (env_ref.flags & SC_SEC_ENV_ALG_REF_PRESENT) > 0
    {
        if env_ref.key_ref_len == 0 {
            rv = SC_ERROR_NOT_SUPPORTED;
            if cfg!(log) {
                wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
            }
            return rv;
        }
        if (env_ref.flags & SC_SEC_ENV_ALG_PRESENT) == 0  ||
            ![SC_ALGORITHM_AES, SC_ALGORITHM_3DES, SC_ALGORITHM_DES].contains(&env_ref.algorithm)
        {
            rv = SC_ERROR_NOT_SUPPORTED;
            if cfg!(log) {
                wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
            }
            return rv;
        }
        #[cfg(not(    v0_17_0))]
        {
            if env_ref.flags & SC_SEC_ENV_KEY_REF_SYMMETRIC == 0 {
                rv = SC_ERROR_NOT_SUPPORTED;
                if cfg!(log) {
                    wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
                }
                return rv;
            }
        }
        #[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
        {
            if (env_ref.algorithm & SC_ALGORITHM_AES) > 0 &&
                ![SC_ALGORITHM_AES_CBC_PAD,
                  SC_ALGORITHM_AES_CBC,
                  SC_ALGORITHM_AES_ECB].contains(&env_ref.algorithm_flags)
            {
                rv = SC_ERROR_NOT_SUPPORTED;
                if cfg!(log) {
                    wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
                }
                return rv;
            }
        }

        let mut vec =   // made for cbc and blockSize == 16
            vec![0_u8,  0x22, 0x01,  0xB8, 0xFF,
                 0x95, 0x01, 0xC0,
                 0x80, 0x01, 0xFF,
                 0x83, 0x01, 0xFF,
                 0x87, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                             0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
         if env_ref.algorithm == SC_ALGORITHM_AES {
            #[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
            { if env_ref.algorithm_flags == SC_ALGORITHM_AES_ECB {vec.truncate(vec.len()-18);} }
            #[cfg(    any(v0_17_0, v0_18_0, v0_19_0))]
            {
                if [4, 5].contains(&env_ref.algorithm_ref) // AES (ECB)
                { vec.truncate(vec.len()-18); }
            }
        }
        else { // then it's SC_ALGORITHM_3DES | SC_ALGORITHM_DES
            vec.truncate(vec.len()-8);
            let pos = vec.len()-9;
            vec[pos] = 8; // IV has len == 8. assuming it's CBC
            if [0, 1].contains(&env_ref.algorithm_ref) // DES/3DES (ECB)
            { vec.truncate(vec.len()-10); }
        }

        /*  transferring the iv is missing below 0.20.0 */
        #[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
        {
            for sec_env_param in &env_ref.params {
                match sec_env_param.param_type {
                    SC_SEC_ENV_PARAM_IV => {
                        assert!(vec.len() >= 16);
                        assert_eq!(u32::from(vec[15]), sec_env_param.value_len);
                        assert_eq!(vec.len(), 16+ sec_env_param.value_len as usize);
                        unsafe { copy_nonoverlapping(sec_env_param.value as *const c_uchar, vec.as_mut_ptr().add(16), sec_env_param.value_len as usize) };
                    },
                    SC_SEC_ENV_PARAM_TARGET_FILE => { continue; }
                    _ => { break; },
                }
            }
/* * /

//                env_ref.algorithm_flags = if crypt_sym.cbc {if crypt_sym.pad_type==BLOCKCIPHER_PAD_TYPE_PKCS5 {SC_ALGORITHM_AES_CBC_PAD} else {SC_ALGORITHM_AES_CBC} } else {SC_ALGORITHM_AES_ECB};
//                env_ref.params[0] = sc_sec_env_param { param_type: SC_SEC_ENV_PARAM_IV, value: crypt_sym.iv.as_mut_ptr() as *mut c_void, value_len: crypt_sym.iv_len.into() };
                // for 3DES/DES use this to select CBC/ECB: with param_type: SC_SEC_ENV_PARAM_DES_ECB or SC_SEC_ENV_PARAM_DES_CBC

                if [SC_ALGORITHM_3DES, SC_ALGORITHM_DES].contains(&env_ref.algorithm) {
                    for i in 0..SC_SEC_ENV_MAX_PARAMS {
                        if vec.len()<=14 {break;}
                        if env_ref.params[i].param_type==SC_SEC_ENV_PARAM_DES_ECB { vec.truncate(vec.len()-10); }
                    }
                }
pub const SC_SEC_ENV_PARAM_DES_ECB           : c_uint = 3;
pub const SC_SEC_ENV_PARAM_DES_CBC           : c_uint = 4;
    #[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
    pub params :          [sc_sec_env_param; SC_SEC_ENV_MAX_PARAMS],
/ * */
        }

        vec[ 4] = (vec.len()-5) as u8;
        vec[10] = env_ref.algorithm_ref as u8;
        vec[13] = env_ref.key_ref[0];

        let mut apdu = sc_apdu::default();
        rv = sc_bytes2apdu_wrapper(card_ctx, &vec, &mut apdu);
        assert_eq!(rv, SC_SUCCESS);
        assert_eq!(apdu.cse, SC_APDU_CASE_3_SHORT);
        rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
        rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
        if rv != SC_SUCCESS {
            if cfg!(log) {
                wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
            }
            return rv;
        }
    }

    else if cfg!(not(any(v0_17_0, v0_18_0, v0_19_0))) {
    #[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
    { // the same for SC_SEC_OPERATION_UNWRAP as for SC_SEC_OPERATION_DECIPHER_RSAPRIVATE
        if SC_SEC_OPERATION_UNWRAP == env_ref.operation  &&
           env_ref.algorithm==SC_ALGORITHM_RSA && (env_ref.flags & SC_SEC_ENV_FILE_REF_PRESENT) > 0
        { // to be set for decipher
            assert!(env_ref.file_ref.len >= 2);
            let path_idx = env_ref.file_ref.len - 2;
            let command = [0x00, 0x22, 0x01, 0xB8, 0x0A, 0x80, 0x01, 0x13, 0x81, 0x02,
                env_ref.file_ref.value[path_idx], env_ref.file_ref.value[path_idx+1],  0x95, 0x01, 0x40];
            let mut apdu = sc_apdu::default();
            rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
            assert_eq!(rv, SC_SUCCESS);
            assert_eq!(apdu.cse, SC_APDU_CASE_3_SHORT);
            rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
//    println!("rv: {}, apdu: {:?}", rv, apdu);
            rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
            if rv != SC_SUCCESS {
                rv = SC_ERROR_KEYPAD_MSG_TOO_LONG;
                if cfg!(log) {
                    wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul
                        (b"'Set SecEnv for RSA Decrypt' failed\0").unwrap());
                    wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
                }
                return rv;
            }
/*
                println!("set_security_env_Unwrap: env_ref.flags: {:X?}", env_ref.flags);                            // 0x12: SC_SEC_ENV_FILE_REF_PRESENT | SC_SEC_ENV_ALG_PRESENT
                println!("set_security_env_Unwrap: env_ref.operation: {:X}", env_ref.operation);                     // 0x06: SC_SEC_OPERATION_UNWRAP
                println!("set_security_env_Unwrap: env_ref.algorithm: {:X?}", env_ref.algorithm);                    // 0x00: SC_ALGORITHM_RSA
                println!("set_security_env_Unwrap: env_ref.algorithm_flags: {:X?}", env_ref.algorithm_flags);        // 0x00:
                println!("set_security_env_Unwrap: env_ref.algorithm_ref: {:X?}", env_ref.algorithm_ref);            // 0x00:
                println!("set_security_env_Unwrap: env_ref.file_ref: {:?}", unsafe{CStr::from_ptr(sc_dump_hex(env_ref.file_ref.value.as_ptr(), env_ref.file_ref.len)).to_str().unwrap()} ); // "41A0"
                println!("set_security_env_Unwrap: env_ref.key_ref: {:X?}", env_ref.key_ref);                        // [0, 0, 0, 0, 0, 0, 0, 0]
                println!("set_security_env_Unwrap: env_ref.key_ref_len: {:X?}", env_ref.key_ref_len);                // 0
                println!("set_security_env_Unwrap: env_ref.target_file_ref: {:?}", unsafe{CStr::from_ptr(sc_dump_hex(env_ref.target_file_ref.value.as_ptr(), env_ref.target_file_ref.len)).to_str().unwrap()} ); // ""
                println!("set_security_env_Unwrap: env_ref.supported_algos[0]: {:X?}", env_ref.supported_algos[0]);  // sc_supported_algo_info { reference: 1, mechanism: 1081, parameters: 0x0, operations: 30, algo_id: sc_object_id { value: [2, 10, 348, 1, 65, 3, 4, 1, 29, FFFFFFFF, FFFFFFFF, FFFFFFFF, FFFFFFFF, FFFFFFFF, FFFFFFFF, FFFFFFFF] }, algo_ref: 4 }
                println!("set_security_env_Unwrap: env_ref.supported_algos[1]: {:X?}", env_ref.supported_algos[1]);  // sc_supported_algo_info { reference: 2, mechanism: 1082, parameters: 0x0, operations: 30, algo_id: sc_object_id { value: [2, 10, 348, 1, 65, 3, 4, 1, 2A, FFFFFFFF, FFFFFFFF, FFFFFFFF, FFFFFFFF, FFFFFFFF, FFFFFFFF, FFFFFFFF] }, algo_ref: 6 }
*/
        }
        else {
            rv = SC_ERROR_NO_CARD_SUPPORT;
            if cfg!(log) {
                wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
            }
            return rv;
        }
    }}
    else {
        rv = SC_ERROR_NO_CARD_SUPPORT;
        if cfg!(log) {
/*
            wr_do_log_t(card_ctx, f_log, line!(), fun, env_ref.flags, CStr::from_bytes_with_nul(b"env_ref.flags: %X\0").unwrap());
            wr_do_log_t(card_ctx, f_log, line!(), fun, env_ref.operation, CStr::from_bytes_with_nul(b"env_ref.operation: %d\0").unwrap());
            wr_do_log_t(card_ctx, f_log, line!(), fun, env_ref.algorithm, CStr::from_bytes_with_nul(b"env_ref.algorithm: %d\0").unwrap());
            wr_do_log_t(card_ctx, f_log, line!(), fun, env_ref.algorithm_flags, CStr::from_bytes_with_nul(b"env_ref.algorithm_flags: %X\0").unwrap());
            wr_do_log_t(card_ctx, f_log, line!(), fun, env_ref.algorithm_ref, CStr::from_bytes_with_nul(b"env_ref.algorithm_ref: %X\0").unwrap());
*/
            wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
        }
        return rv;
    }

    if cfg!(log) {
        wr_do_log_tu(card_ctx, f_log, line!(), fun, SC_SUCCESS, unsafe { sc_strerror(SC_SUCCESS) }, CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
    }
    SC_SUCCESS
}

/* Should this be restricted by inspecting the padding for correctness ? */
/* decipher:  Engages the deciphering operation.  Card will use the
 *   security environment set in a call to set_security_env or
 *   restore_security_env.
 *
 *  Status Words while processing:
 *  While sending (flag SC_APDU_FLAGS_CHAINING set conditionally) transmit of chunks returns 0x9000 for cos5, until all data are sent. The last transmit returns e.g. SW 0x6100,
 *  meaning, there are 256 bytes or more to fetch, or a one only transmit for keylen<=2048 returns e.g. 0x61E0 or 0x6100.
 *  decrypted data for keylen<=2048 can be easily, automatically fetched with regular commands called by sc_transmit_apdu (sc_get_response, iso7816_get_response;
 *  olen  = apdu->resplen (before calling sc_single_transmit; after calling sc_single_transmit, all commands that return a SM 0x61?? set apdu->resplen to 0)
 *  olen get's passed to sc_get_response, which is the total size of output buffer offered.
 *  For keylen>2048
 00 C0 00 00 00
 */
/*
 * What it does The function currently relies on, that the crgram_len==keylen_bytes i.o. to control amount of bytes to expect from get_response (if keylen_bytes>256)
 * @apiNote
 * @param
 * @return  error code or number of bytes written into out
 */
/* see pkcs15-sec.c:sc_pkcs15_decipher This operation is dedicated to be used with RSA keys only ! */
extern "C" fn acos5_decipher(card_ptr: *mut sc_card, crgram_ref_ptr: *const c_uchar, crgram_len: usize,
                                                       out_ptr:        *mut c_uchar,     outlen: usize) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || crgram_ref_ptr.is_null() || out_ptr.is_null() {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let mut rv;
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun  = CStr::from_bytes_with_nul(b"acos5_decipher\0").unwrap();
    if cfg!(log) {
        wr_do_log_tt(card_ctx, f_log, line!(), fun, crgram_len, outlen,
                     CStr::from_bytes_with_nul(b"called with: in_len: %zu, out_len: %zu\0").unwrap());
    }
    assert!(outlen >= crgram_len);
    assert_eq!(crgram_len, get_sec_env_mod_len(card));
//println!("acos5_decipher          called with: in_len: {}, out_len: {}", crgram_len, outlen);

    #[cfg(enable_acos5_ui)]
    {
        if get_ui_ctx(card).user_consent_enabled == 1 {
            /* (Requested by DGP): on signature operation, ask user consent */
            rv = acos5_ask_user_consent();
            if rv < 0 {
                unsafe { wr_do_log_sds(card_ctx, f_log, line!(), fun,CStr::from_bytes_with_nul(b"User consent denied\0")
                    .unwrap().as_ptr(), rv, sc_strerror(rv), CStr::from_bytes_with_nul(b"%s: %d (%s)\n\0").unwrap()) };
                return rv;
            }
        }
    }

    let command = [0, 0x2A, 0x80, 0x84, 0x02, 0xFF, 0xFF, 0xFF]; // will replace lc, cmd_data and le later; the last 4 bytes are placeholders only for sc_bytes2apdu_wrapper
    let mut apdu = sc_apdu::default();
    rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
    assert_eq!(rv, SC_SUCCESS);
    assert_eq!(apdu.cse, SC_APDU_CASE_4_SHORT);

    let mut vec = vec![0_u8; outlen];
    apdu.data    = crgram_ref_ptr;
    apdu.datalen = crgram_len;
    apdu.lc      = crgram_len;
    apdu.resp    = vec.as_mut_ptr();
    apdu.resplen = outlen;
    apdu.le      = std::cmp::min(crgram_len, SC_READER_SHORT_APDU_MAX_RECV_SIZE);
    if apdu.lc > card.max_send_size {
        apdu.flags |= SC_APDU_FLAGS_CHAINING;
    }

    set_is_running_cmd_long_response(card, true); // switch to false is done by acos5_get_response
    rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
    rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
    if rv != SC_SUCCESS || apdu.resplen==0
    {
        if cfg!(log) {
            wr_do_log_tt(card_ctx, f_log, line!(), fun, apdu.sw1, apdu.sw2,
                         CStr::from_bytes_with_nul(b"### 0x%02X%02X: decipher failed or \
                         it's impossible to retrieve the answer from get_response ###\0").unwrap());
        }
        /* while using pkcs11-tool -l -t
        it may happen, that a sign-key get's tested with a hash algo unsupported by compute_signature, thus it must revert to use acos5_decipher,
        but the key isn't generated with decrypt capability: Then fake a success here, knowing, that a verify signature will fail
        Update: this doesn't help, check_sw kicks in and aborts on error 0x6A80 */
        if rv == SC_ERROR_INCORRECT_PARAMETERS { // 0x6A80 error code get's transformed by iso7816_check_sw to SC_ERROR_INCORRECT_PARAMETERS
            apdu.sw1 = 0x90;
            apdu.sw2 = 0x00;
            if cfg!(log) {
                wr_do_log(card_ctx, f_log, line!(), fun, CStr::from_bytes_with_nul(b"### \
                decipher failed with error code 0x6A80: Multiple possible reasons for the failure; a likely harmless \
                one is, that the key is not capable to decipher but was used for deciphering (maybe called from \
                compute_signature, i.e. the intent was signing with a hash algo that compute_signature doesn't support; \
                compute_signature reverts to decipher for any hash algo other than SHA-1 or SHA-256) ###\0").unwrap() );
            }
        }
        assert!(rv<0);
        return rv;
    }
    let vec_len = std::cmp::min(crgram_len, apdu.resplen);
    vec.truncate(vec_len);

    if get_is_running_compute_signature(card) {
        set_is_running_compute_signature(card, false);
        rv = 0;
    }
    else { // assuming plaintext was EME-PKCS1-v1_5 encoded before encipher: Now remove the padding
        let sec_env_algo_flags : c_uint = get_sec_env(card).algorithm_flags;
//println!("\nacos5_decipher:             in_len: {}, out_len: {}, sec_env_algo_flags: 0x{:X}, input data: {:X?}", crgram_len, outlen, sec_env_algo_flags,  unsafe {from_raw_parts(crgram_ref_ptr, crgram_len)});
//println!("\nacos5_decipher:             in_len: {}, out_len: {}, sec_env_algo_flags: 0x{:X},output data: {:X?}", crgram_len, outlen, sec_env_algo_flags,  vec);
        rv = me_pkcs1_strip_02_padding(&mut vec); // returns length of padding to be removed from vec such that net message/plain text remains
        if rv < SC_SUCCESS {
            if (SC_ALGORITHM_RSA_RAW & sec_env_algo_flags) == SC_ALGORITHM_RSA_RAW {
                rv = 0;
            }
            else {
                if cfg!(log) {
                    unsafe { wr_do_log_sds(card_ctx, f_log, line!(), fun,CStr::from_bytes_with_nul(b"returning with: Failed strip_02_padding !\0")
                        .unwrap().as_ptr(), rv, sc_strerror(rv), CStr::from_bytes_with_nul(b"%s rv: %d (%s)\n\0").unwrap()) };
                }
                return rv;
            }
        }
    }
    assert!(rv >= 0);
    assert!((vec_len as c_int) >= rv);
    unsafe { copy_nonoverlapping(vec.as_ptr(), out_ptr, vec_len - (rv as usize)) };

    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(), fun, (vec_len as c_int) - rv,
                    CStr::from_bytes_with_nul(RETURNING_INT).unwrap());
    }
    (vec_len as c_int) - rv
}


/*
1. DO very very carefully inspect where acos5_compute_signature transfers the operation to acos5_decipher:
   It MUST NOT happen, that an attacker can use acos5_compute_signature to pass arbitrary data to acos5_decipher, except of Length hLen (HashLength which is max 64 bytes)

2. This should be the place to check, that the integer representing the 'message' is smaller than the integer representing the RSA key modulus !
   BUT, that's not possible here (there is no knowledge here about the RSA key modulus) !
   EMSA-PKCS1-v1_5:
       emLen = RSA key modulus length in bytes, e.g. for a 4096 bit key: 512
       EM starts with bytes 0x00, 0x01  (EM = 0x00 || 0x01 || PS || 0x00 || T).
       Thus the modulus must start with bytes > 0x00, 0x01, e.g. the minimum is 0x00, 0x02:
           Check in acos5_gui when generating a key pair, that this condition is met

   EMSA-PSS:
      11. Set the leftmost 8emLen - emBits bits of the leftmost octet in
       maskedDB to zero.

      12. Let EM = maskedDB || H || 0xbc.

      emBits must be less than  int RSA_bits(const RSA *rsa); // RSA_bits() returns the number of significant bits.



   Definition :
         DigestInfo ::= SEQUENCE {
          digestAlgorithm DigestAlgorithm,
          digest OCTET STRING
      }

   In the following, digestAlgorithm includes the tag for SEQUENCE and a length byte (behind SEQUENCE)
   Input allowed: optional_padding  +  digestAlgorithm  +  digest

   For RSASSA-PKCS1-v1_5:
       Only for sha1 and sha256, as an exception, both optional_padding + digestAlgorithm, may be omitted from input, for all other digestAlgorithm is NOT optional.

   RSASSA-PSS : Only works with SC_ALGORITHM_RSA_RAW declared in acos5_init()

 * What it does
 Ideally this function should be adaptive, meaning it works for SC_ALGORITHM_RSA_RAW (SC_ALGORITHM_RSA_PAD_NONE)
 as well as for e.g. SC_ALGORITHM_RSA_PAD_PKCS1

 The function currently relies on, that data_len==keylen_bytes i.o. to control amount of bytes to expect from get_response (if keylen_bytes>256)
 It's not safe to use outlen as indicator for  keylen_bytes, e.g.: pkcs15-crypt --sign --key=5 --input=test_in_sha1.hex --output=test_out_sig_pkcs1.hex --sha-1 --pkcs1 --pin=12345678
 uses outlen==1024

 * @apiNote
 * @param
 * @return  error code (neg. value) or number of bytes written into out
 */
#[cfg_attr(feature = "cargo-clippy", allow(clippy::suspicious_else_formatting))]
extern "C" fn acos5_compute_signature(card_ptr: *mut sc_card, data_ref_ptr: *const c_uchar, data_len: usize,
                                                                   out_ptr:   *mut c_uchar,   outlen: usize) -> c_int
{
    if data_len == 0 || outlen == 0 {
        return 0;
    }
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || data_ref_ptr.is_null() || out_ptr.is_null() ||
        outlen < 64 { // cos5 supports RSA beginning from moduli 512 bits = 64 bytes
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    assert!(data_len <= outlen);
    assert!(data_len <= 512); // cos5 supports max RSA 4096 bit keys
//println!("acos5_compute_signature called with: in_len: {}, out_len: {}", data_len, outlen);
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun   = CStr::from_bytes_with_nul(b"acos5_compute_signature\0").unwrap();
    if cfg!(log) {
        wr_do_log_tt(card_ctx, f_log, line!(), fun, data_len, outlen,
                     CStr::from_bytes_with_nul(b"called with: in_len: %zu, out_len: %zu\0").unwrap());
    }
    set_is_running_compute_signature(card, false); // thus is an info valuable only when delegating to acos5_decipher

//    #[cfg(    any(v0_17_0, v0_18_0))]
//    let mut rv = SC_SUCCESS;
//    #[cfg(not(any(v0_17_0, v0_18_0)))]
    let mut rv; // = SC_SUCCESS;
    //   sha1     sha256  +md2/5 +sha1  +sha224  +sha256  +sha384  +sha512
    if ![20_usize, 32,     34,    35,    47,      51,      67,      83, get_sec_env_mod_len(card)].contains(&data_len) {
        rv = SC_ERROR_NOT_SUPPORTED;
        unsafe { wr_do_log_sds(card_ctx, f_log, line!(), fun,CStr::from_bytes_with_nul(b"returning with: Inadmissible data_len !\0")
            .unwrap().as_ptr(), rv, sc_strerror(rv), CStr::from_bytes_with_nul(b"%s: %d (%s)\n\0").unwrap()) };
        return rv;
    }
    #[allow(non_snake_case)]
    let digestAlgorithm_sha1      = [0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14];
    #[allow(non_snake_case)]
    let digestAlgorithm_sha256    = [0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20];

    let mut vec_in : Vec<c_uchar> = Vec::with_capacity(512);
    /*
       if data_len==20, assume it's a SHA-1   digest and prepend digestAlgorithm
       if data_len==32, assume it's a SHA-256 digest and prepend digestAlgorithm
     */
    if      data_len == 20 {
        vec_in.extend_from_slice(&digestAlgorithm_sha1[..]);
    }
    else if data_len == 32 {
        vec_in.extend_from_slice(&digestAlgorithm_sha256[..]);
    }
    vec_in.extend_from_slice(unsafe { from_raw_parts(data_ref_ptr, data_len) });

    let sec_env_algo_flags = get_sec_env(card).algorithm_flags;
//println!("\nacos5_compute_signature:             in_len: {}, out_len: {}, sec_env_algo_flags: 0x{:X}, input data: {:X?}", vec_in.len(), outlen, sec_env_algo_flags,  vec_in);
    let digest_info =
        if (SC_ALGORITHM_RSA_RAW & sec_env_algo_flags) == 0 { vec_in.as_slice() } // then vec_in IS digest_info
        else { // (SC_ALGORITHM_RSA_RAW & sec_env_algo_flags) == SC_ALGORITHM_RSA_RAW (in v0.20.0 that's the same as sec_env_algo_flags == SC_ALGORITHM_RSA_PAD_NONE)
//println!("acos5_compute_signature: (SC_ALGORITHM_RSA_RAW & sec_env_algo_flags) == SC_ALGORITHM_RSA_RAW");
            match me_pkcs1_strip_01_padding(&vec_in) { // TODO possibly also try pkcs1_strip_PSS_padding
                Ok(digest_info) => digest_info,
                Err(e) => {
                    if cfg!(dev_relax_signature_constraints_for_raw) && data_len==get_sec_env_mod_len(card) {
//println!("acos5_compute_signature: dev_relax_signature_constraints_for_raw is active");
                        set_is_running_compute_signature(card, true);
                        rv = acos5_decipher(card, data_ref_ptr, data_len, out_ptr, outlen);
                        wr_do_log_tu(card_ctx, f_log, line!(), fun, rv, unsafe { sc_strerror(rv) },
                                 CStr::from_bytes_with_nul(RETURNING_INT_CSTR).unwrap());
                        return rv;
/*
We are almost lost here (or have to reach into one's bag of tricks): We know, that we''ll have to switch to acos5_decipher and:
The "7.4.3.9. RSA Private Key Decrypt" command requires an input data length that must be the same as the RSA key length being used.
It's unknown here what is the RSA key length and we can't reliably deduce that from the parameters:
One of the tests of pkcs11-tool sends this:
acos5_compute_signature: called with: data_len: 34, outlen: 1024
Trick: cache last security env setting, retrieve file id (priv) and deduce key length from file size. The commands were:
00 22 01 B6 0A 80 01 10 81 02 41 F3 95 01 40 ."........A...@
00 22 01 B8 0A 80 01 13 81 02 41 F3 95 01 40 ."........A...@
*/
                    }
                    else {
                        /* */
                        if [35, 51].contains(&vec_in.len()) /* TODO && &vec_in.as_slice()[0..15] != &digestAlgorithm_ripemd160[..]*/ {
                            if (vec_in.len() == 35 && vec_in.as_slice()[0..15] == digestAlgorithm_sha1[..]) ||
                               (vec_in.len() == 51 && vec_in.as_slice()[0..19] == digestAlgorithm_sha256[..])
                            {
                                &vec_in[..]
                            }
                            else {
                                return e;
                            }
                        }
                        /* */
                        else if e != SC_ERROR_WRONG_PADDING || vec_in[vec_in.len() - 1] != 0xbc {
                            wr_do_log_tu(card_ctx, f_log, line!(), fun, e, unsafe { sc_strerror(e) },
                                         CStr::from_bytes_with_nul(b"returning (input is neither EMSA-PKCS1-v1_5 nor EMSA-PSS encoded) with: %d (%s)\n\0").unwrap());
                            return e;
                        }
                        else {
                            return -1;
                            /* forward to acos5_decipher only, if this is really secure; a pss padding can't be detected unambiguously */
//                          set_is_running_compute_signature(card, true);
//                          return acos5_decipher(card, data_ref_ptr, data_len, out_ptr, outlen);
                        }
                    }
/* */
                }
            }
        };
//println!("digest_info.len(): {}, digest_info: {:X?}", digest_info.len(), digest_info);
    if digest_info.is_empty() { // if there is no content to sign, then don't sign
        return SC_SUCCESS;
    }

    // id_rsassa_pkcs1_v1_5_with_sha512_256 and id_rsassa_pkcs1_v1_5_with_sha3_256 also have a digest_info.len() == 51

    if  ( digest_info.len() == 35 /*SHA-1*/ || digest_info.len() == 51 /*SHA-256*/)  && // this first condition is superfluous but get's a faster decision in many cases
        ((digest_info.len() == 35 && digest_info[..15]==digestAlgorithm_sha1[..])   ||
         (digest_info.len() == 51 && digest_info[..19]==digestAlgorithm_sha256[..]) )
    {
//println!("acos5_compute_signature: digest_info.len(): {}, digest_info[..15]==digestAlgorithm_sha1[..]: {}, digest_info[..19]==digestAlgorithm_sha256[..]: {}", digest_info.len(), digest_info[..15]==digestAlgorithm_sha1[..], digest_info[..19]==digestAlgorithm_sha256[..]);
        #[cfg(enable_acos5_ui)]
        {
            if get_ui_ctx(card).user_consent_enabled == 1 {
                /* (Requested by DGP): on signature operation, ask user consent */
                rv = acos5_ask_user_consent();
                if rv < 0 {
                    unsafe { wr_do_log_sds(card_ctx, f_log, line!(), fun,CStr::from_bytes_with_nul(b"returning with: User consent denied\0")
                        .unwrap().as_ptr(), rv, sc_strerror(rv), CStr::from_bytes_with_nul(b"%s: %d (%s)\n\0").unwrap()) };
                    return rv;
                }
            }
        }

        // SHA-1 and SHA-256 hashes, what the card can handle natively
        let hash = &digest_info[if digest_info.len()==35 {15} else {19} ..];
        set_is_running_cmd_long_response(card, true); // switch to false is done by acos5_get_response
        let func_ptr = unsafe { (*(*sc_get_iso7816_driver()).ops).compute_signature.unwrap() };
        rv = unsafe { func_ptr(card, hash.as_ptr(), hash.len(), out_ptr, outlen) };
        if rv <= 0 && cfg!(log) {
            wr_do_log_t(card_ctx, f_log, line!(), fun, rv,
                        CStr::from_bytes_with_nul(b"iso7816_compute_signature failed or apdu.resplen==0. rv: %d\0").unwrap());
//            return rv;
        }
        /* temporary: "decrypt" signature (out) to stdout * /
        encrypt_public_rsa(card, out_ptr, data_len);
        / * */
    }
    else {   /* for other digests than SHA-1/SHA-256 */
        if cfg!(log) {
            let fmt = CStr::from_bytes_with_nul(b"### Switch to acos5_decipher, because \
                acos5_compute_signature can't handle the hash algo ###\0").unwrap();
            wr_do_log(card_ctx, f_log, line!(), fun, fmt);
        }
        /* digest_info.len() is from SC_ALGORITHM_RSA_RAW/SC_ALGORITHM_RSA_PAD_NONE or SC_ALGORITHM_RSA_PAD_PKCS1 */
        /* is_any_known_digestAlgorithm or ? could go further and compare digestAlgorithm to known ones as well
           With that done, a possible attacker can control nothing but the hash value (and signature scheme to be used)
           TODO implement delaying, if consecutive trials to sign are detected, revoke PIN verification etc.
             or enable an additional layer where user MUST accept or deny sign operation (see DNIE) */
//println!("is_any_known_digestAlgorithm(digest_info): {}", is_any_known_digestAlgorithm(digest_info));
        if (SC_ALGORITHM_RSA_PAD_PKCS1 & sec_env_algo_flags) > 0 && is_any_known_digestAlgorithm(digest_info)
        {
/* calling me_get_encoding_flags is not necessary, it's done within sc_pkcs1_encode anyway.
   Here just for curiosity/inspection * /
            let mut pflags = 0;
            let mut sflags = 0;
            rv = me_get_encoding_flags(card_ctx, sec_env_algo_flags | SC_ALGORITHM_RSA_HASH_NONE,
                                       get_rsa_caps(card), &mut pflags, &mut sflags);
println!("pflags: {}, sflags: {}", pflags, sflags);
            if rv != SC_SUCCESS {
                return rv;
            }
/ * */
            let mut vec_len = std::cmp::min(outlen, get_sec_env_mod_len(card));
            let mut vec = vec![0_u8; vec_len];
            rv = unsafe { sc_pkcs1_encode(card_ctx, (sec_env_algo_flags | SC_ALGORITHM_RSA_HASH_NONE) as c_ulong, digest_info.as_ptr(),
                                          digest_info.len(), vec.as_mut_ptr(), &mut vec_len, vec_len *
                                          if cfg!(any(v0_17_0, v0_18_0, v0_19_0)) {1} else {8}) };
            if rv != SC_SUCCESS {
                return rv;
            }
            set_is_running_compute_signature(card, true);
            rv = acos5_decipher(card, vec.as_ptr(), vec_len, out_ptr, outlen);
        }
        else if (SC_ALGORITHM_RSA_RAW  & sec_env_algo_flags) > 0 && data_len==get_sec_env_mod_len(card) &&
            (is_any_known_digestAlgorithm(digest_info) || cfg!(dev_relax_signature_constraints_for_raw))
        {
//            match me_pkcs1_strip_01_padding(&vec_in) { // TODO possibly also try pkcs1_strip_PSS_padding
//                Ok(digest_info) => digest_info,
//                Err(e) => {}
//            }
            set_is_running_compute_signature(card, true);
            rv = acos5_decipher(card, data_ref_ptr, data_len, out_ptr, outlen);
        }
/*
        else if cfg!(not(any(v0_17_0, v0_18_0))) {
        #[       cfg(not(any(v0_17_0, v0_18_0)))]
        {
            if (SC_ALGORITHM_RSA_PAD_PSS & sec_env_algo_flags) > 0 /*&& is_any_known_digestAlgorithm(digest_info.len()*/) {
                rv = 0; // do nothing
/*
sc_pkcs1_encode with SC_ALGORITHM_RSA_PAD_PSS does work only since v0.20.0
when pkcs1_strip_PSS_padding works
                    let mut vec = vec![0u8; 512];
                    let mut vec_len = std::cmp::min(512, outlen);
                    if cfg!(any(v0_17_0, v0_18_0, v0_19_0)) {
                        rv = unsafe { sc_pkcs1_encode(card_ctx, (sec_env_algo_flags | SC_ALGORITHM_RSA_HASH_NONE) as c_ulong, digest_info.as_ptr(),
                                                      digest_info.len(), vec.as_mut_ptr(), &mut vec_len, vec_len) };
                    }
                    else {
                        rv = unsafe { sc_pkcs1_encode(card_ctx, (sec_env_algo_flags | SC_ALGORITHM_RSA_HASH_NONE) as c_ulong, digest_info.as_ptr(),
                                                      digest_info.len(), vec.as_mut_ptr(), &mut vec_len, vec_len*8) };
                    }
                    if rv != SC_SUCCESS {
                        return rv;
                    }
                    rv = acos5_decipher(card, data_ref_ptr, data_len, out_ptr, outlen);
*/
            }
            else {
                rv = 0; // do nothing
            }
        }}
*/
        //TODO temporarily allow suspicious_else_formatting
        else {
            rv = 0; // do nothing and live with a verification error
        }
        /* temporary: "decrypt" signature (out) to stdout */
        if rv>0 { // EM = 0x00 || 0x02 || PS || 0x00 || M.
//            let tmp_buf = [0u8,2,   4,247,125,36,98,255,144,111,47,96,32,249,19,77,251,200,199,87,16,99,178,159,210,55,1,254,66,236,11,   0, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32];
//            encrypt_public_rsa(card, tmp_buf.as_ptr() /*out_ptr*/, /*data_len*/ tmp_buf.len()/*outlen*/);
        }

        if cfg!(log) {
            wr_do_log_t(card_ctx, f_log, line!(), fun, rv,
                CStr::from_bytes_with_nul(b"returning from acos5_compute_signature with: %d\n\0").unwrap());
        }
//        return rv;
    }
    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(), fun, data_len as c_int,
                    CStr::from_bytes_with_nul(RETURNING_INT).unwrap());
    }
    rv
//    data_len as c_int
} // acos5_compute_signature

/* Implementation for RSA_WRAPPED_AES_KEY with template entries for receiving sym. key: CKA_TOKEN=TRUE and CKA_EXTRACTABLE=FALSE.
   i.e. it's assumed that the unwrapped key is of AES type ! */
#[cfg(not(any(v0_17_0, v0_18_0, v0_19_0)))]
extern "C" fn acos5_unwrap(card_ptr: *mut sc_card, crgram: *const c_uchar, crgram_len: usize) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun  = CStr::from_bytes_with_nul(b"acos5_unwrap\0").unwrap();
    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(), fun, crgram_len, CStr::from_bytes_with_nul(b"called with crgram_len: %zu\0").unwrap());
    }

    let mut vec = vec![0; crgram_len];
    let rv = acos5_decipher(card, crgram, crgram_len, vec.as_mut_ptr(), vec.len());
    if rv < SC_SUCCESS {
        unsafe { wr_do_log_sds(card_ctx, f_log, line!(), fun,CStr::from_bytes_with_nul(b"returning with failure\0")
            .unwrap().as_ptr(), rv, sc_strerror(rv), CStr::from_bytes_with_nul(b"%s: %d (%s)\n\0").unwrap()) };
        return rv;
    }
    vec.truncate(rv as usize);
    let klen = vec.len();
    assert!([16, 24, 32].contains(&klen));
//println!("\n\nUnwrapped {} key bytes: {:X?}\n", klen, vec);
    let mut dp = unsafe { Box::from_raw(card.drv_data as *mut DataPrivate) };
    if dp.is_unwrap_op_in_progress {
        assert!(usize::from(dp.sym_key_rec_cnt) >= klen+3);
        vec.reserve_exact(usize::from(dp.sym_key_rec_cnt));
        vec.insert(0, 0x80|dp.sym_key_rec_idx);
        vec.insert(1, 0);
        vec.insert(2, if klen==32 {0x22} else if klen==24 {0x12} else {2});
        while vec.len() < usize::from(dp.sym_key_rec_cnt) { vec.push(0); }
        let mut path = sc_path { len: 2, ..sc_path::default() };
        unsafe { copy_nonoverlapping(dp.sym_key_file_id.to_be_bytes().as_ptr(), path.value.as_mut_ptr(), 2) };
        unsafe { sc_select_file(card, &path, null_mut()) };
        /* TODO This only works if Login-PIN is the same as required for SC_AC_OP_UPDATE of file dp.sym_key_file_id */
        unsafe { sc_update_record(card, u32::from(dp.sym_key_rec_idx), vec.as_ptr(), vec.len(), SC_RECORD_BY_REC_NR) };
        dp.is_unwrap_op_in_progress = false;
    }
    card.drv_data = Box::into_raw(dp) as *mut c_void;

    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(), fun, rv,
                    CStr::from_bytes_with_nul(RETURNING_INT).unwrap());
    }
    rv
}

/*
 * Implements sc_card_operations function 'delete_record'
 * @see opensc_sys::opensc pub struct sc_card_operations
 * In the narrower sense, deleting a record is impossible: It's part of a file that may be deleted.
 * In the broader sense, cos5 considers any record with first byte==00 as empty (see cos5 command 'append_record'),
 * thus this command will zeroize all record content
 * @apiNote
 * @param  rec_nr starting from 1
 * @return number of erasing zero bytes written to record, otherwise an error code
 */
extern "C" fn acos5_delete_record(card_ptr: *mut sc_card, rec_nr: c_uint) -> c_int
{
    if card_ptr.is_null() || unsafe { (*card_ptr).ctx.is_null() } || rec_nr==0 || rec_nr>0xFF {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card       = unsafe { &mut *card_ptr };
    let card_ctx = unsafe { &mut *card.ctx };
    let f_log = CStr::from_bytes_with_nul(CRATE).unwrap();
    let fun  = CStr::from_bytes_with_nul(b"acos5_delete_record\0").unwrap();
    if cfg!(log) {
        wr_do_log_t(card_ctx, f_log, line!(), fun, rec_nr, CStr::from_bytes_with_nul(b"called with rec_nr: %u\0").unwrap());
    }
    let zero_buf = [0; 0xFF];
    acos5_update_record(card, rec_nr,zero_buf.as_ptr(), zero_buf.len(), 0)
/*
    let command = [0, 0xDC, rec_nr as u8, 4, 1, 1];
    let mut apdu = sc_apdu::default();
    let mut rv = sc_bytes2apdu_wrapper(card_ctx, &command, &mut apdu);
    assert_eq!(rv, SC_SUCCESS);
    assert_eq!(apdu.cse, SC_APDU_CASE_3_SHORT);
    apdu.lc      = zero_buf.len();
    apdu.datalen = zero_buf.len();
    apdu.data    = zero_buf.as_ptr();
    apdu.flags = SC_RECORD_BY_REC_NR | SC_APDU_FLAGS_NO_RETRY_WL;

    rv = unsafe { sc_transmit_apdu(card, &mut apdu) };
    if rv == SC_SUCCESS && unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) } == SC_SUCCESS  {
        zero_buf.len() as c_int
    }
    else if apdu.sw1 != 0x6C {
        rv
    }
    else {
        assert!(apdu.sw2 as usize <= zero_buf.len());
        /* retransmit */
        apdu.lc      = apdu.sw2 as usize;
        apdu.datalen = apdu.sw2 as usize;
        rv = unsafe { sc_transmit_apdu(card, &mut apdu) }; if rv != SC_SUCCESS { return rv; }
        rv = unsafe { sc_check_sw(card, apdu.sw1, apdu.sw2) };
        if rv != SC_SUCCESS {rv} else {apdu.lc as c_int}
    }
*/
}
extern "C" fn acos5_append_record(card_ptr: *mut sc_card,
                                  buf_ptr: *const c_uchar, count: usize, _flags: c_ulong) -> c_int
{
    if card_ptr.is_null() || buf_ptr.is_null() || count==0 {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let card = unsafe { &mut *card_ptr };
    let buf      = unsafe { std::slice::from_raw_parts(buf_ptr, count) };
    manage_common_update(card, 0, buf, 0, false)
}

/* returns how many bytes were read or an error code */
/* read_binary is also responsible for get_key and takes appropriate actions, such that get_key is NOT publicly available
   OpenSC doesn't know the difference (fdb 1 <-> 9): It always calls for transparent files: read_binary
   shall be called solely by sc_read_binary, which cares for dividing into chunks !! */
extern "C" fn acos5_read_binary(card_ptr: *mut sc_card, idx: c_uint,
                                buf_ptr: *mut c_uchar, count: usize, flags: c_ulong) -> c_int
{
    if card_ptr.is_null() || buf_ptr.is_null() || count==0 {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let idx = idx as u16;
    let count = count as u16;
    let card = unsafe { &mut *card_ptr };
    let buf      = unsafe { std::slice::from_raw_parts_mut(buf_ptr, usize::from(count)) };
    common_read(card, idx, buf, flags, true)
}

extern "C" fn acos5_read_record(card_ptr: *mut sc_card, rec_nr: c_uint,
                                buf_ptr: *mut c_uchar, count: usize, _flags: c_ulong) -> c_int
{
    if card_ptr.is_null() || buf_ptr.is_null() || count==0 /* || count>255*/ {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let rec_nr = rec_nr as u16;
    let count = count as u16;
    let card = unsafe { &mut *card_ptr };
    let buf      = unsafe { std::slice::from_raw_parts_mut(buf_ptr, usize::from(count)) };
    manage_common_read(card, rec_nr, buf, SC_RECORD_BY_REC_NR, false)
}

extern "C" fn acos5_update_binary(card_ptr: *mut sc_card, idx: c_uint,
                                  buf_ptr: *const c_uchar, count: usize, flags: c_ulong) -> c_int
{
    if card_ptr.is_null() || buf_ptr.is_null() || count==0 {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    let idx = idx as u16;
    let count = count as u16;
    let card = unsafe { &mut *card_ptr };
    let buf      = unsafe { std::slice::from_raw_parts(buf_ptr, usize::from(count)) };
    common_update(card, idx, buf, flags, true)
}

extern "C" fn acos5_update_record(card_ptr: *mut sc_card, rec_nr: c_uint,
                                  buf_ptr: *const c_uchar, count: usize, _flags: c_ulong) -> c_int
{
    if card_ptr.is_null() || buf_ptr.is_null() || count==0 {
        return SC_ERROR_INVALID_ARGUMENTS;
    }
    assert!(rec_nr>0);
    let rec_nr = rec_nr as u16;
    let count = count as u16;
    let card = unsafe { &mut *card_ptr };
    let buf      = unsafe { std::slice::from_raw_parts(buf_ptr, usize::from(count)) };
    manage_common_update(card, rec_nr, buf, SC_RECORD_BY_REC_NR, false)
}
