/*
 * acos5_64.d Support for ACOS5-64 smart cards
 *
 * Copyright (C) 2017  Carsten Blüggel <carblue@geekmail.de>
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
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

module acos5_64;

version(ACOSMODE_V3_FIPS_140_2L3) {
	version=SESSIONKEYSIZE24;
}


import core.stdc.config : c_ulong;
import core.stdc.locale : setlocale, LC_ALL;
import core.stdc.string : memset, memcpy, memcmp, strlen/*, strcasecmp*/;
import core.stdc.stdlib : realloc, free, malloc, calloc;
import std.stdio : stdout, stderr, writeln, writefln, File, snprintf;
import std.string : toStringz, fromStringz, lastIndexOf, CaseSensitive, representation;
import std.exception : enforce, assumeUnique;
import std.format;
import std.range : take, retro;
import std.array;
import std.regex;
import std.traits : EnumMembers;
import std.typecons : Tuple;


version(GNU) { // gdc compiler
	import std.algorithm : min, max, clamp, equal, find, canFind, any;
//import gcc.attribute;
}
else { // DigitalMars or LDC compiler
	import std.algorithm.comparison : min, max, clamp, equal;
	import std.algorithm.searching : /*count,*/ find, canFind, any /*,all*/;
}

version(Windows) {
	import core.sys.windows.dll : SimpleDllMain;

version(unittest) {} else
	mixin SimpleDllMain;
}


/* import OpenSC */
import libopensc.asn1 : sc_asn1_find_tag, sc_asn1_put_tag, sc_asn1_entry, sc_copy_asn1_entry, SC_ASN1_OCTET_STRING, SC_ASN1_CTX, SC_ASN1_OPTIONAL,
	sc_format_asn1_entry, sc_asn1_decode, SC_ASN1_PRESENT;
import libopensc.cardctl : SC_CARDCTL, SC_CARDCTL_GENERIC_BASE, SC_CARDCTL_ERASE_CARD, SC_CARDCTL_GET_DEFAULT_KEY, SC_CARDCTL_LIFECYCLE_GET,
					SC_CARDCTL_GET_SE_INFO, SC_CARDCTL_GET_CHV_REFERENCE_IN_SE, SC_CARDCTL_PKCS11_INIT_TOKEN, SC_CARDCTL_PKCS11_INIT_PIN,
					SC_CARDCTL_LIFECYCLE_SET, SC_CARDCTL_GET_SERIALNR,
					SC_CARDCTRL_LIFECYCLE, SC_CARDCTRL_LIFECYCLE_ADMIN, SC_CARDCTRL_LIFECYCLE_USER, SC_CARDCTRL_LIFECYCLE_OTHER;

import libopensc.internal : sc_atr_table;

version(OPENSC_VERSION_LATEST) // libopensc 0.16.0 binary exports these functions, whereas 0.15.0 does NOT; the first two are missing, the last 2 are duplicazed in this driver
	import libopensc.internal : sc_pkcs1_strip_01_padding, sc_pkcs1_strip_02_padding, _sc_card_add_rsa_alg, _sc_match_atr;

import libopensc.log : sc_dump_hex, sc_do_log, SC_LOG_DEBUG_NORMAL, log;
import libopensc.opensc; // sc_format_path, SC_ALGORITHM_RSA, sc_print_path, sc_file_get_acl_entry
import libopensc.types;// : sc_path, sc_atr, sc_file, sc_serial_number, SC_MAX_PATH_SIZE, SC_PATH_TYPE_PATH, sc_apdu, SC_AC_OP_GENERATE;
import libopensc.errors;
import scconf.scconf : scconf_block, scconf_find_blocks, scconf_get_str, scconf_get_bool;
import libopensc.cards : SC_CARD_TYPE_ACOS5_64_V2, SC_CARD_TYPE_ACOS5_64_V3;
import libopensc.sm;

import libopensc.pkcs15 : sc_pkcs15_card, sc_pkcs15_object, sc_pkcs15_pubkey, SC_PKCS15_TOKEN_PRN_GENERATION, sc_pkcs15_prkey_info, sc_pkcs15_print_id, SC_PKCS15_TYPE_PRKEY_RSA, SC_PKCS15_TYPE_PUBKEY_RSA,
	sc_pkcs15_prkey, sc_pkcs15_der, sc_pkcs15_auth_info, SC_PKCS15_PRKEY_USAGE_SIGN, SC_PKCS15_TYPE_CLASS_MASK, sc_pkcs15_prkey_rsa;
import pkcs15init.pkcs15init : /*sc_profile,*/ sc_pkcs15init_operations, sc_pkcs15init_authenticate, sc_pkcs15init_delete_by_path, sc_pkcs15init_create_file, SC_PKCS15INIT_SO_PIN, SC_PKCS15INIT_USER_PIN;
import pkcs15init.profile : file_info, sc_profile/*, sc_profile_get_file*/;

/* import crypto : openssl, sodium */
version(USE_SODIUM) {
	import deimos.sodium.core : sodium_init;
	import deimos.sodium.utils : sodium_malloc, sodium_free, sodium_mlock, sodium_munlock, sodium_mprotect_noaccess, sodium_mprotect_readwrite, sodium_mprotect_readonly;
	import deimos.sodium.version_ : sodium_version_string;
}

import deimos.openssl.des : DES_cblock, const_DES_cblock, DES_KEY_SZ; //, DES_key_schedule, DES_SCHEDULE_SZ /* is not fixed length, as dep. on DES_LONG */, DES_LONG /*c_ulong*/;
import deimos.openssl.bn;
import deimos.openssl.conf;
import deimos.openssl.evp;
import deimos.openssl.err;
import deimos.openssl.rand : RAND_bytes;

//from acos5_64_h
enum ACOS5_64_OBJECT_REF_FLAG_LOCAL = 0x80;
enum ACOS5_64_CRYPTO_OBJECT_REF_MIN	= 0x01; // 0x81;
enum ACOS5_64_CRYPTO_OBJECT_REF_MAX	= 0x0F; // 0xFF;

enum ERSA_Key_type : ubyte {
	Public_Key                          = 0, // Public Key

	Standard_for_Signing_and_Decrypting = 1, // Private non-CRT key capable of RSA Private Key Sign and Decrypt
	Standard_for_Decrypting             = 2, // Private non-CRT key capable of RSA Private Key Decrypt (only)
	CRT_for_Signing_and_Decrypting      = 4, // Private     CRT key capable of RSA Private Key Sign and Decrypt
	CRT_for_Decrypting_only             = 5, // Private     CRT key capable of RSA Private Key Decrypt (only)
}

enum EFDB : ubyte {
// Working EF:
	Transparent_EF     = SC_FILE_EF.SC_FILE_EF_TRANSPARENT, //1,
	Linear_Fixed_EF    = SC_FILE_EF.SC_FILE_EF_LINEAR_FIXED,// 2,
	Linear_Variable_EF = SC_FILE_EF.SC_FILE_EF_LINEAR_VARIABLE, // 4,
	Cyclic_EF          = SC_FILE_EF.SC_FILE_EF_CYCLIC,// 6, // rarely used		
	// Internal EF:
	RSA_Key_EF         = 0x09,     // ==  8+Transparent_EF,  not record based ( Update Binary )		
	// There can be a maximum of 0x1F Global PINs, 0x1F Local PINs, 0x1F Global Keys, and 0x1F Local Keys at a given time. (1Fh==31)
	CHV_EF             = 0x0A,  // ==  8+Linear_Fixed_EF,     record based ( Update Record ) DF or MF shall contain only one CHV file. Every record in the CHV file will have a fixed length of 21 bytes each
	Symmetric_key_EF   = 0x0C,  // ==  8+Linear_Variable_EF,  record based ( Update Record ) DF or MF shall contain only one sym file. Every record in the symmetric key file shall have a maximum of 37 bytes
	// Proprietary EF:
	SE_EF    	         = 0x1C,  // ==18h+Linear_Variable_EF,  record based ( Update Record ) DF or MF shall use only one SE File. An SE file can have up to 0x0F identifiable records. (0Fh==15)
	// DF types:
	DF                 = ISO7816_FILE_TYPE_DF, //0x38,  // == 0b0011_1000; common DF type mask == DF : (file_type_in_question & DF) == DF for this enum
	MF                 = 0x3F,  // == 0b0011_1111; common DF type mask == DF : (file_type_in_question & DF) == DF for this enum
}
mixin FreeEnumMembers!EFDB;

ubyte iEF_FDB_to_structure(EFDB FDB) { auto result = cast(ubyte)(FDB & 7); if (result>0 && result<7) return result; else return 0; } 

/*
   DigestInfo ::= SEQUENCE {
     digestAlgorithm DigestAlgorithmIdentifier,
     digest Digest
   }
In the following naming, digestInfoPrefix is everything from the ASN1 representaion of DigestInfo, except the trailing digest bytes
*/
enum DigestInfo_Algo_RSASSA_PKCS1_v1_5 : ubyte  { // contents from RFC 8017 are examples, some not recommended for new apps, some in specific schemes; SHA3 not yet mentioned in RFC 8017
/*
	id_rsassa_pkcs1_v1_5_with_md2,        // md2WithRSAEncryption, // id_md2, not recommended
	id_rsassa_pkcs1_v1_5_with_md5,        // md5WithRSAEncryption, // id_md5, not recommended
*/
	id_rsassa_pkcs1_v1_5_with_sha1,       // sha1WithRSAEncryption,       // id_sha1, not recommended, backwards compatibility only

	id_rsassa_pkcs1_v1_5_with_sha224,     // sha224WithRSAEncryption,     // id_sha224
	id_rsassa_pkcs1_v1_5_with_sha256,     // sha256WithRSAEncryption,     // id_sha256
	id_rsassa_pkcs1_v1_5_with_sha384,
	id_rsassa_pkcs1_v1_5_with_sha512,
	id_rsassa_pkcs1_v1_5_with_sha512_224,
	id_rsassa_pkcs1_v1_5_with_sha512_256,
//
	id_rsassa_pkcs1_v1_5_with_sha3_224,
	id_rsassa_pkcs1_v1_5_with_sha3_256,
	id_rsassa_pkcs1_v1_5_with_sha3_384,
	id_rsassa_pkcs1_v1_5_with_sha3_512,
/*
version(D_LP64) {
id_rsassa_pkcs1_v1_5_with_blake2b160, // https://tools.ietf.org/html/rfc7693
id_rsassa_pkcs1_v1_5_with_blake2b256,
id_rsassa_pkcs1_v1_5_with_blake2b384,
id_rsassa_pkcs1_v1_5_with_blake2b512,
}
else {
id_rsassa_pkcs1_v1_5_with_blake2s128,
id_rsassa_pkcs1_v1_5_with_blake2s160,
id_rsassa_pkcs1_v1_5_with_blake2s224,
id_rsassa_pkcs1_v1_5_with_blake2s256,
}
*/
	id_rsassa_pkcs1_v1_5_maxcount_unused // usefull as excluded limit in .min .. .max
}
mixin FreeEnumMembers!DigestInfo_Algo_RSASSA_PKCS1_v1_5;

enum Usage {
	/* HT */
	None,
	/* AT 1*/
	Pin_Verify_and_SymKey_Authenticate,
	SymKey_Authenticate,
	Pin_Verify,
	/* DST 4*/
	Sign_PKCS1_priv,  // algo (10) can be infered; the key type RSA priv. must match what is stored in FileID parameter
	Verify_PKCS1_pub, // algo (10) can be infered; the key type RSA publ. must match what is stored in FileID parameter
	Sign_9796_priv,   // algo (11) can be infered; the key type RSA priv. must match what is stored in FileID parameter
	Verify_9796_pub,  // algo (11) can be infered; the key type RSA publ. must match what is stored in FileID parameter
	/* CT_asym 8*/
	Decrypt_PSO_priv,
	Decrypt_PSO_SMcommand_priv,
	Decrypt_PSO_SMresponse_priv,
	Decrypt_PSO_SMcommandResponse_priv,
	Encrypt_PSO_pub,
	Encrypt_PSO_SMcommand_pub,
	Encrypt_PSO_SMresponse_pub,
	Encrypt_PSO_SMcommandResponse_pub,

	/* CT_sym */

	/* CCT 16*/
	Session_Key_SM,
	Session_Key,
	Local_Key1_SM,
	Local_Key1,
}
mixin FreeEnumMembers!Usage;


struct acos5_64_private_data {
	ubyte[2*DES_KEY_SZ] card_key2;
	ubyte[2*DES_KEY_SZ] host_key1;
//	sm_cwa_token_data		ifd;
	ubyte[  DES_KEY_SZ] cwa_session_ifd_sn;
	ubyte[  DES_KEY_SZ] cwa_session_ifd_rnd;
	ubyte[4*DES_KEY_SZ]	cwa_session_ifd_k;

	ubyte[  DES_KEY_SZ]	card_challenge; // cwa_session.card_challenge.ptr
	/* it's necessary to know, whether a call to function acos5_64_decipher originated from function acos5_64_compute_signature or not.
	 * call_to_compute_signature_in_progress is set to true, when function acos5_64_compute_signature is entered, and reset to false when returning.
	 */
	bool call_to_compute_signature_in_progress;

	sc_security_env         security_env;
	acos5_64_se_info*       se_info;

version(ENABLE_ACOS5_64_UI)
	 ui_context_t           ui_ctx;
}

enum /*BlockCipherModeOfOperation*/ {
	ECB,
	CBC,
	DAC, /* usage in encrypt_algo must pass DAC and desired DAC_length;  acos does CBC-MAC like in withdrawn FIPS PUB 113, but with TDES instead of DES, with an IV!=0 and DAC-length is 4 bytes  */
	// more? ,
	blockCipherModeOfOperation_maxcount_unused // usefull as excluded limit in .min .. .max
}

enum SubDO_Tag : ubyte {
	Algorithm                = 0x80,

	KeyFile_RSA              = 0x81,
	// or
	ID_Pin_Key_Local_Global  = 0x83,
	HP_Key_Session           = 0x84, // High Priority: If this is present, ID_Pin_Key_Local_Global will be ignored (if present too)
	Initial_Vector           = 0x87,

	UQB                      = 0x95, // Usage Qualifier Byte 
}
mixin FreeEnumMembers!SubDO_Tag;

struct CRT_Tags {
	SubDO_Tag[] mandatory_And;
	SubDO_Tag[] mandatory_OneOf;
	SubDO_Tag[] optional_SymKey; // only for sym.Key, i.e. ID_Pin_Key_Local_Global or HP_Key_Session: the Initial_Vector may be required or not
}

struct Algorithm_Possible {
	uba list;
}
struct UQB_Possible {
	ubyte   mask;
	uba list;
}
struct ID_Pin_Key_Local_Global_Possible {
	ubyte   mask;
	uba list;
}

enum Template_Tag : ubyte {
	HT      = 0xAA,
	AT      = 0xA4, 
	DST     = 0xB6,
	CT_asym = 0xB8+1,
	CT_sym  = 0xB8+0,
	CCT     = 0xB4,
	NA      = 0x00,
}
mixin FreeEnumMembers!Template_Tag;

enum SMDO_Tag : ubyte { // Secure Messaging Data Object Tags
	Plain_Value                                           = 0x81, // Length variable
	Padding_content_indicator_byte_followed_by_cryptogram = 0x87, // Length variable
	Command_header_SMCLA_INS_P1_P2                        = 0x89, // Length = 4
	Cryptographic_Checksum                                = 0x8E, // Length = 4
	Original_P3_in_an_ISO_OUT_command                     = 0x97, // Length = 1
	Processing_status_word_SW1SW2_of_the_command          = 0x99, // Length = 2
}
mixin FreeEnumMembers!SMDO_Tag;

enum SM_Extend {
	SM_CCT,
	SM_CCT_AND_CT_sym
}
mixin FreeEnumMembers!SM_Extend;

enum {
	ACS_ACOS5_64_V2, // v2.00: Smart Card/CryptoMate64
	ACS_ACOS5_64_V3, // v3.00: Smart Card/CryptoMate Nano
	// insert here
	ATR_zero,
	ATR_maxcount_unused,
}

struct DI_data { // DigestInfo_data
	string             hashAlgorithmOID;
	ubyte              hashAlgorithmName; // it's enum value is the index in DI_table
	ubyte              hashLength;
	ubyte              digestInfoLength;
	bool               allow;
	bool               compute_signature_possible_without_rawRSA;
	immutable(ubyte)[] digestInfoPrefix;
}


alias  uba        = ubyte[];
alias  ub4        = ubyte[4];
alias  ub8        = ubyte[8];
alias  ub16       = ubyte[16];
alias  ub24       = ubyte[24];
//ias iub8        = immutable(ubyte)[8];

alias TSMarguments = Tuple!(
	 int,       "cse"           /* APDU case */
	,SM_Extend, "sm_extend"     /* APDU case */
	,uba,       "cla_ins_p1_p2" /* APDU case */
	,ubyte*,    "key"
	,ub8,       "ssc_iv"
	,ubyte,     "p3"
	,uba,       "cmdData"
);


//////////////////////////////////////////////////

/* the nice thing about these mixin templates is avoiding code duplication, but currently lost __LINE__ pointing to the "correct" source code line having rv<0:
TODO check if __LINE__ can point to where the mixin was used; currently all log messages report the mixin template definition source location */
mixin template transmit_apdu(alias functionName) {
	int transmit_apdu_do() {
		int rv_priv;
		if ((rv_priv=sc_transmit_apdu(card, &apdu)) < 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, functionName,
				"APDU transmit failed\n");
		return rv_priv;
	}
}

mixin template transmit_apdu_strerror(alias functionName) {
	int transmit_apdu_strerror_do() {
		int rv_priv;
		if ((rv_priv=sc_transmit_apdu(card, &apdu)) < 0)
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, functionName,
				"APDU transmit failed: %d (%s)\n", rv_priv, sc_strerror(rv_priv));
		return rv_priv;
	}
}

mixin template alloc_rdata_rapdu(alias functionName) {
	int alloc_rdata_rapdu_do() {
		int rv_priv;
		if ((rv_priv=rdata.alloc(rdata, &rapdu)) < 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, functionName,
				"cannot allocate remote APDU");
		return rv_priv;
	}
}

mixin template log_scope_exit(alias functionName) {
	void log_scope_exit_do() {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, functionName,
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, functionName,
				"returning with: %d\n", rv);
	}
}


//////////////////////////////////////////////////

immutable(DI_data[]) DI_table = [ // DigestInfo_table
/*
	DI_data("1.2.840.113549.2.2",      id_rsassa_pkcs1_v1_5_with_md2,        16, 34, false, false, cast(immutable(ubyte)[]) x"30 20 30 0c 06 08 2a 86 48 86 f7 0d 02 02 05 00 04 10"),
	DI_data("1.2.840.113549.2.5",      id_rsassa_pkcs1_v1_5_with_md5,        16, 34, false, false, cast(immutable(ubyte)[]) x"30 20 30 0c 06 08 2a 86 48 86 f7 0d 02 05 05 00 04 10"),
*/
	DI_data("1.3.14.3.2.26",           id_rsassa_pkcs1_v1_5_with_sha1,       20, 35, true,  true,  cast(immutable(ubyte)[]) x"30 21 30 09 06 05 2b 0e 03 02 1a 05 00 04 14"),

	DI_data("2.16.840.1.101.3.4.2.4",  id_rsassa_pkcs1_v1_5_with_sha224,     28, 47, true,  false, cast(immutable(ubyte)[]) x"30 2d 30 0d 06 09 60 86 48 01 65 03 04 02 04 05 00 04 1c"),
	DI_data("2.16.840.1.101.3.4.2.1",  id_rsassa_pkcs1_v1_5_with_sha256,     32, 51, true,  true,  cast(immutable(ubyte)[]) x"30 31 30 0d 06 09 60 86 48 01 65 03 04 02 01 05 00 04 20"),
	DI_data("2.16.840.1.101.3.4.2.2",  id_rsassa_pkcs1_v1_5_with_sha384,     48, 67, true,  false, cast(immutable(ubyte)[]) x"30 41 30 0d 06 09 60 86 48 01 65 03 04 02 02 05 00 04 30"),
	DI_data("2.16.840.1.101.3.4.2.3",  id_rsassa_pkcs1_v1_5_with_sha512,     64, 83, true,  false, cast(immutable(ubyte)[]) x"30 51 30 0d 06 09 60 86 48 01 65 03 04 02 03 05 00 04 40"),
	DI_data("2.16.840.1.101.3.4.2.5",  id_rsassa_pkcs1_v1_5_with_sha512_224, 28, 47, true,  false, cast(immutable(ubyte)[]) x"30 2d 30 0d 06 09 60 86 48 01 65 03 04 02 05 05 00 04 1c"),
	DI_data("2.16.840.1.101.3.4.2.6",  id_rsassa_pkcs1_v1_5_with_sha512_256, 32, 51, true,  false, cast(immutable(ubyte)[]) x"30 31 30 0d 06 09 60 86 48 01 65 03 04 02 06 05 00 04 20"),

	DI_data("2.16.840.1.101.3.4.2.7",  id_rsassa_pkcs1_v1_5_with_sha3_224,   28, 47, true,  false, cast(immutable(ubyte)[]) x"30 2d 30 0d 06 09 60 86 48 01 65 03 04 02 07 05 00 04 1c"),
	DI_data("2.16.840.1.101.3.4.2.8",  id_rsassa_pkcs1_v1_5_with_sha3_256,   32, 51, true,  false, cast(immutable(ubyte)[]) x"30 31 30 0d 06 09 60 86 48 01 65 03 04 02 08 05 00 04 20"),
	DI_data("2.16.840.1.101.3.4.2.9",  id_rsassa_pkcs1_v1_5_with_sha3_384,   48, 67, true,  false, cast(immutable(ubyte)[]) x"30 41 30 0d 06 09 60 86 48 01 65 03 04 02 09 05 00 04 30"),
	DI_data("2.16.840.1.101.3.4.2.10", id_rsassa_pkcs1_v1_5_with_sha3_512,   64, 83, true,  false, cast(immutable(ubyte)[]) x"30 51 30 0d 06 09 60 86 48 01 65 03 04 02 0a 05 00 04 40"),
/*
version(D_LP64) { //Blak2s is not mentioned in PKCS#2.2
data("1.3.6.1.4.1.1722.12.2.1.5",  id_rsassa_pkcs1_v1_5_with_blake2b160, 20, 41, true,  false, cast(immutable(ubyte)[]) x"30 27 30 0F 06 0B 2b 06 01 04 01 8D 3A 0c 02 01 05 05 00 04 14"),
data("1.3.6.1.4.1.1722.12.2.1.8",  id_rsassa_pkcs1_v1_5_with_blake2b256, 32, 53, true,  false, cast(immutable(ubyte)[]) x"30 33 30 0F 06 0B 2b 06 01 04 01 8D 3A 0c 02 01 08 05 00 04 20"),
data("1.3.6.1.4.1.1722.12.2.1.12", id_rsassa_pkcs1_v1_5_with_blake2b384, 48, 69, true,  false, cast(immutable(ubyte)[]) x"30 43 30 0F 06 0B 2b 06 01 04 01 8D 3A 0c 02 01 0c 05 00 04 30"),
data("1.3.6.1.4.1.1722.12.2.1.16", id_rsassa_pkcs1_v1_5_with_blake2b512, 64, 85, true,  false, cast(immutable(ubyte)[]) x"30 53 30 0F 06 0B 2b 06 01 04 01 8D 3A 0c 02 01 10 05 00 04 40"),
}
else {
data("1.3.6.1.4.1.1722.12.2.2.4",  id_rsassa_pkcs1_v1_5_with_blake2s128, 16, 41, true,  false, cast(immutable(ubyte)[]) x"30 23 30 0F 06 0B 2b 06 01 04 01 8D 3A 0c 02 02 04 05 00 04 10"),
data("1.3.6.1.4.1.1722.12.2.2.5",  id_rsassa_pkcs1_v1_5_with_blake2s160, 20, 41, true,  false, cast(immutable(ubyte)[]) x"30 27 30 0F 06 0B 2b 06 01 04 01 8D 3A 0c 02 02 05 05 00 04 14"),
data("1.3.6.1.4.1.1722.12.2.2.7",  id_rsassa_pkcs1_v1_5_with_blake2s224, 28, 41, true,  false, cast(immutable(ubyte)[]) x"30 2F 30 0F 06 0B 2b 06 01 04 01 8D 3A 0c 02 02 07 05 00 04 1c"),
data("1.3.6.1.4.1.1722.12.2.2.8",  id_rsassa_pkcs1_v1_5_with_blake2s256, 32, 41, true,  false, cast(immutable(ubyte)[]) x"30 33 30 0F 06 0B 2b 06 01 04 01 8D 3A 0c 02 02 08 05 00 04 20"),
}
*/
];



immutable ubyte[1]  ubZero = cast(ubyte)0;
immutable ubyte[1]  ubOne  = cast(ubyte)1;
immutable ubyte[1]  ubTwo  = cast(ubyte)2;

immutable(const(EVP_CIPHER)*[blockCipherModeOfOperation_maxcount_unused]) cipher_TDES; // TODO TDES won't be included in openssl any more beginning with version 1.1.0

immutable sc_path MF_path = sc_path( cast(immutable(ubyte)[SC_MAX_PATH_SIZE]) x"3F00 0000000000000000000000000000", 2, 0, 0, SC_PATH_TYPE_PATH /*all following bytes of aid: zero*/);

version(ACOSMODE_V2)
	private immutable(char)[46]  chip_name  = "ACS ACOS5-64 (v2.00: Smart Card/CryptoMate64)"; // C-style null-terminated string equivalent, +1 for literal-implicit \0
else
	private immutable(char)[49]  chip_name  = "ACS ACOS5-64 (v3.00: Smart Card/CryptoMate Nano)";

private immutable(char)[ 9]  chip_shortname = "acos5_64";
//private immutable(char)[57][2] ATR_colon        = [ "3B:BE:96:00:00:41:05:20:00:00:00:00:00:00:00:00:00:90:00",
//                                                    "3B:BE:96:00:00:41:05:30:00:00:00:00:00:00:00:00:00:90:00"];

private immutable(char)[57] ATR_V2_colon =          "3B:BE:96:00:00:41:05:20:00:00:00:00:00:00:00:00:00:90:00";
private immutable(char)[57] ATR_V3_colon =          "3B:BE:96:00:00:41:05:30:00:00:00:00:00:00:00:00:00:90:00";

private immutable(char)[57]  ATR_mask  =    "FF:FF:FF:FF:FF:FF:FF:FF:00:00:00:00:00:00:00:00:FF:FF:FF";

/* ATR Table list. */
private __gshared sc_atr_table[ATR_maxcount_unused] acos5_64_atrs = [ // immutable(sc_atr_table)[3]
	sc_atr_table(
		ATR_V2_colon.ptr,               // atr
		ATR_mask.ptr,                   // atrmask "FF:FF:FF:FF:FF:FF:FF:FF:00:00:00:00:00:00:00:00:00:FF:FF",
		chip_shortname.ptr,             // name
		SC_CARD_TYPE_ACOS5_64_V2,       // type
		SC_CARD_FLAG_RNG,               // flags
		null                            // card_atr  scconf_block*  fill this in acos5_64_init, or done by opensc d?
	),
	sc_atr_table(
		ATR_V3_colon.ptr,
		ATR_mask.ptr,
		chip_shortname.ptr,
		SC_CARD_TYPE_ACOS5_64_V3,
		SC_CARD_FLAG_RNG, // flags
		null
	),
	sc_atr_table(null, null, null, 0, 0, null) // list end marker all zero
];

__gshared sc_card_operations*  iso_ops_ptr;
private __gshared sc_card_operations        acos5_64_ops;
private __gshared sc_pkcs15init_operations  acos5_64_pkcs15init_ops;

/* Module definition for card driver */
private __gshared sc_card_driver  acos5_64_drv = sc_card_driver(
	chip_name.ptr,      /**< (name):       Full name for acos5_64 card driver */
	chip_shortname.ptr, /**< (short_name): Short name for acos5_64 card driver */
	null,               /**< (ops):        Pointer to acos5_64_ops (acos5_64 card driver operations), assigned later by sc_get_acos5_64_driver */
	acos5_64_atrs.ptr,  /**< (atr_map):    Pointer to list of card ATR's handled by this driver */
	2,                  /**< (natrs):      Number of atr's to check for this driver */
	null                /**< (dll):        Card driver module  (seems to be unused) */
);

// the OpenSC version, this driver implementation is based on/does support.
private __gshared const(char[7]) module_version = "0.16.0";  // uint major = 0, minor = 16, fix = 0;

version(ENABLE_TOSTRING)
auto writer = appender!string();

BN_CTX* bn_ctx;


/* Information Structures for Building CRT Templates (which Tags for what type of Template; for SE-File, ManageSecurityEnvironment MSE and acos5_64_set_security_env) */
immutable(                        CRT_Tags[Template_Tag]) aa_crt_tags; // =
immutable(              Algorithm_Possible[Template_Tag]) aa_alg_poss;
immutable(                    UQB_Possible[Template_Tag]) aa_uqb_poss;
immutable(ID_Pin_Key_Local_Global_Possible[Template_Tag]) aa_idpk_poss;

//////////////////////////////////////////////////


private uba construct_SMcommand(int SC_APDU_CASE, SM_Extend sm_extend, in uba CLA_INS_P1_P2, in ubyte* key, ref ubyte[8] ssc_iv,  ubyte P3=0, uba cmdData=null)
{
	uba result;
	assert(4==CLA_INS_P1_P2.length);
	assert(P3<=240);
	assert(canFind([SC_APDU_CASE_1, SC_APDU_CASE_2_SHORT, SC_APDU_CASE_3_SHORT, SC_APDU_CASE_4_SHORT], SC_APDU_CASE));

	ub4  SMCLA_INS_P1_P2 = CLA_INS_P1_P2[];
	SMCLA_INS_P1_P2[0] |= 0x0C;
	result = SMCLA_INS_P1_P2 ~ ubZero;

	uba mac_indataPadded = [ubyte(SMDO_Tag.Command_header_SMCLA_INS_P1_P2), ubyte(4)] ~ SMCLA_INS_P1_P2;
	switch (SC_APDU_CASE) {
		case SC_APDU_CASE_2_SHORT:
			result           ~= [ubyte(SMDO_Tag.Original_P3_in_an_ISO_OUT_command), ubyte(1) , P3];
			mac_indataPadded ~= [ubyte(SMDO_Tag.Original_P3_in_an_ISO_OUT_command), ubyte(1) , P3];
			break;
		case SC_APDU_CASE_3_SHORT, SC_APDU_CASE_4_SHORT:
			result           ~= [ubyte(SMDO_Tag.Plain_Value), P3] ~ cmdData;
			mac_indataPadded ~= [ubyte(SMDO_Tag.Plain_Value), P3] ~ cmdData;
			break;
		default:
			break;
	}

	ub8 mac_outdataPadded;
	if (mac_indataPadded.length%8)
		mac_indataPadded ~= ubyte(0x80);
	while (mac_indataPadded.length%8)
		mac_indataPadded ~= ubyte(0x00);// assert(equal(5.repeat().take(4), [ 5, 5, 5, 5 ]));

	sm_incr_ssc(ssc_iv); // ready for SM-mac'ing // The sequence number (seq#) n is used as the initial vector in the CBC calculation
	if (8!=encrypt_algo_cbc_mac(mac_indataPadded, key, ssc_iv.ptr, mac_outdataPadded.ptr, cipher_TDES[DAC], false))
		return null;

	result ~= [ubyte(SMDO_Tag.Cryptographic_Checksum), ubyte(4)] ~ mac_outdataPadded[0..4];
	result[4] = cast(ubyte)(result.length-5);
	return result;//.dup;
}

private int check_SMresponse(sc_apdu* apdu, int SC_APDU_CASE, SM_Extend sm_extend, in uba CLA_INS_P1_P2, in ubyte* key, ref ubyte[8] ssc_iv,  ubyte P3=0) {
	assert(4==CLA_INS_P1_P2.length);
	
	uba mac_indataPadded = [ubyte(SMDO_Tag.Command_header_SMCLA_INS_P1_P2), ubyte(4)] ~ CLA_INS_P1_P2 ~
		[ubyte(SMDO_Tag.Processing_status_word_SW1SW2_of_the_command), ubyte(2), cast(ubyte)apdu.sw1, cast(ubyte)apdu.sw2];
	mac_indataPadded[2] |= 0x0C;

	if (canFind([SC_APDU_CASE_2_SHORT, SC_APDU_CASE_4_SHORT], SC_APDU_CASE)) {
/*
the response data must be unwrapped, possibly it's encrypted and must be decrypted
*/
		if (sm_extend==SM_Extend.SM_CCT)
			mac_indataPadded ~= [ubyte(SMDO_Tag.Plain_Value), P3] ~ apdu.resp[0..apdu.resplen];
		else {
			mac_indataPadded ~= [ubyte(SMDO_Tag.Padding_content_indicator_byte_followed_by_cryptogram), ubyte(0), ubyte(0)] ~ apdu.resp[0..apdu.resplen];
		}
	}

	if (mac_indataPadded.length%8)
		mac_indataPadded ~= ubyte(0x80);
	while (mac_indataPadded.length%8)
		mac_indataPadded ~= ubyte(0x00);

	ub8 mac_outdataPadded;
	sm_incr_ssc(ssc_iv);
	if (8!=encrypt_algo_cbc_mac(mac_indataPadded, key, ssc_iv.ptr, mac_outdataPadded.ptr, cipher_TDES[DAC], false))
		return SC_ERROR_SM_ENCRYPT_FAILED;
	return SC_ERROR_SM_INVALID_CHECKSUM* !(equal(mac_outdataPadded[0..4], apdu.mac[0..4]) && 4==apdu.mac_len);
}


unittest {
	version(SESSIONKEYSIZE24)
		ub24 random_key;
	else
		ub16 random_key;
	assert(1==RAND_bytes(random_key.ptr, random_key.length));
	ub8  random_iv;
	assert(1==RAND_bytes(random_iv.ptr, random_iv.length));

	ub4  CLA_INS_P1_P2 = [0x00, 0x0E, 0x00, 0x00];
	TSMarguments smArguments;
	smArguments = TSMarguments(SC_APDU_CASE_1, SM_Extend.SM_CCT, CLA_INS_P1_P2, random_key.ptr, random_iv, 0, null);

	uba  SMcommand = construct_SMcommand(smArguments[]);
	assert(equal(SMcommand[0..7], [0x0C, 0x0E, 0x00, 0x00, 0x06, 0x8E, 0x04][0..7]));

	ubyte P3 = 2;
	ubyte[2] offset = [0, 5];
	SMcommand = construct_SMcommand(SC_APDU_CASE_3_SHORT, SM_Extend.SM_CCT, CLA_INS_P1_P2, random_key.ptr, random_iv, P3, offset);
	assert(equal(SMcommand[0..11], [0x0C, 0x0E, 0x00, 0x00, 0x0A, 0x81, P3, 0x00, 0x05, 0x8E, 0x04][0..11]));

	CLA_INS_P1_P2 = [0x00, 0x84, 0x00, 0x00];
	P3 = 8;
	SMcommand = construct_SMcommand(SC_APDU_CASE_2_SHORT, SM_Extend.SM_CCT, CLA_INS_P1_P2, random_key.ptr, random_iv, P3);
	assert(equal(SMcommand[0..10], [0x0C, 0x84, 0x00, 0x00, 0x09, 0x97, 0x01, P3, 0x8E, 0x04][0..10]));

	CLA_INS_P1_P2 = [0x00, 0x2A, 0x9E, 0x9A];
	P3 = 20;
	ubyte[20] hash = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20];
	SMcommand = construct_SMcommand(SC_APDU_CASE_4_SHORT, SM_Extend.SM_CCT, CLA_INS_P1_P2, random_key.ptr, random_iv, P3, hash);
	assert(equal(SMcommand[0..29], [0x0C, 0x2A, 0x9E, 0x9A, 0x1C, 0x81, P3, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20, 0x8E, 0x04][0..29]));
	writeln("PASSED: construct_SMcommand");
}

uba  get_cwa_session_enc(ref const sm_cwa_session cwa) {
	uba result = cwa.session_enc.dup;
version(SESSIONKEYSIZE24)
	result ~= cwa.icc.k[8..16];
	return result;
}
void set_cwa_session_enc(ref sm_cwa_session cwa, uba key) {
	cwa.session_enc  = key[ 0..16];
version(SESSIONKEYSIZE24)
	cwa.icc.k[8..16] = key[16..24];
}

uba  get_cwa_session_mac(ref const sm_cwa_session cwa) {
	uba result = cwa.session_mac.dup;
version(SESSIONKEYSIZE24)
	result ~= cwa.ifd.k[8..16];
	return result;
}
void set_cwa_session_mac(ref sm_cwa_session cwa, uba key) {
	cwa.session_mac  = key[ 0..16];
version(SESSIONKEYSIZE24)
	cwa.ifd.k[8..16] = key[16..24];
}
///////////////
uba  get_cwa_keyset_enc(ref const sm_cwa_session cwa) {
	uba result = cwa.cwa_keyset.enc.dup;
version(SESSIONKEYSIZE24)
	result ~= cwa.icc.k[0..8];
	return result;
}
void set_cwa_keyset_enc(ref sm_cwa_session cwa, uba key) {
	cwa.cwa_keyset.enc  = key[ 0..16];
version(SESSIONKEYSIZE24)
	cwa.icc.k[0..8]     = key[16..24];
}

uba  get_cwa_keyset_mac(ref const sm_cwa_session cwa) {
	uba result = cwa.cwa_keyset.mac.dup;
version(SESSIONKEYSIZE24)
	result ~= cwa.ifd.k[0..8];
	return result;
}
void set_cwa_keyset_mac(ref sm_cwa_session cwa, uba key) {
	cwa.cwa_keyset.mac  = key[ 0..16];
version(SESSIONKEYSIZE24)
	cwa.ifd.k[0..8]     = key[16..24];
}


extern(C) int rt_init(); // in Windows, a DLL_PROCESS_ATTACH calls rt_init(); what is the equivalent in Linux?
extern(C) int rt_term(); // in Windows, a DLL_PROCESS_DETACH calls rt_term(); what is the equivalent in Linux?

shared static this() {
	setlocale (LC_ALL, "C"); // char* currentlocale =
	/* Initialise the openssl library */
	ERR_load_crypto_strings();
	OpenSSL_add_all_algorithms();
	OPENSSL_config(null);
	bn_ctx = BN_CTX_new();

	version(SESSIONKEYSIZE24)
		const(EVP_CIPHER)*[blockCipherModeOfOperation_maxcount_unused] local_cipher_TDES = [EVP_des_ede3(), EVP_des_ede3_cbc(), EVP_des_ede3_cbc()];
	else
		const(EVP_CIPHER)*[blockCipherModeOfOperation_maxcount_unused] local_cipher_TDES = [EVP_des_ede(),  EVP_des_ede_cbc(),  EVP_des_ede_cbc()];
	cipher_TDES = assumeUnique(local_cipher_TDES);

	CRT_Tags[Template_Tag] local_aa_crt_tags = [// mandatory_And    // mandatory_OneOf                           // optional
		// if SubDO_Tag.Algorithm) is required, it's always within the .mandatory_And
		// Pin or Key identifier may be in .mandatory_And || .mandatory_OneOf
		HT     : CRT_Tags([      Algorithm ]),
		AT     : CRT_Tags([ UQB,            ID_Pin_Key_Local_Global ]),
		DST    : CRT_Tags([ UQB, Algorithm, KeyFile_RSA ]),
		CT_asym: CRT_Tags([ UQB, Algorithm, KeyFile_RSA ]),
		CT_sym : CRT_Tags([ UQB, Algorithm ],                         [ ID_Pin_Key_Local_Global, HP_Key_Session ], [ Initial_Vector ]),
		CCT    : CRT_Tags([ UQB, Algorithm ],                         [ ID_Pin_Key_Local_Global, HP_Key_Session ], [ Initial_Vector ]),
	];

	aa_crt_tags = assumeUnique(local_aa_crt_tags);

	Algorithm_Possible[Template_Tag] local_aa_alg_poss = [ // defaults shall be the first entry
		HT     : Algorithm_Possible([       0x21 /*SHA256*/   ,      ubyte(0x20) /*SHA1*/ ]),
		AT     : Algorithm_Possible([]),
		DST    : Algorithm_Possible([ ubyte(0x10) /*PKCS#1 Padding generated by card for Sign; or removed for verify; also for generate key pair; all RSA*/
																															,  ubyte(0x11)/* ISO 9796-2 scheme 1 Padding*/ ]),
		CT_asym: Algorithm_Possible([ ubyte(0x13) /*Decrypt */, cast(ubyte)0x12 /*Encrypt, both RSA */ ]),
		CT_sym : Algorithm_Possible([ ubyte(0x06) /* AES-CBC*/, cast(ubyte)0x04 /* AES-ECB*/
																 ,ubyte(0x07) /* AES-CBC*/, cast(ubyte)0x05 /* AES-ECB*/
																 ,ubyte(0x02) /*TDES-CBC*/, cast(ubyte)0x00 /*TDES-ECB*/
																 ,ubyte(0x03) /* DES-CBC*/, cast(ubyte)0x01 /* DES-ECB*/ ]),
		CCT    : Algorithm_Possible([ ubyte(0x02) /*TDES-CBC*/, cast(ubyte)0x03 /* DES-CBC; NOT SECURE !*/ ]),
	];
	aa_alg_poss = assumeUnique(local_aa_alg_poss);

	UQB_Possible[Template_Tag] local_aa_uqb_poss = [
		HT     : UQB_Possible(0xFF, []),
		AT     : UQB_Possible(0x88, [0x88/*Pin_Verify_and_SymKey_Authenticate*/, 0x80/*SymKey_Authenticate*/, 0x08/*Pin_Verify*/]),
		DST    : UQB_Possible(0xC0, [0x40/*private*/, 0x80/*public*/,  0x40, 0x80]),
		CT_asym: UQB_Possible(0x70, [0x40/*PSO*/, 0x50/*PSO+SM in Command Data*/, 0x60/*PSO+SM in Response Data*/, 0x70/*PSO+SM in Command and Response Data*/, 0x40, 0x50, 0x60, 0x70]),
		CT_sym : UQB_Possible(0x70, [0x30/*SM*/, 0x40/*PSO*/]),
		CCT    : UQB_Possible(0x70, [0x30/*SM*/, 0x40/*PSO*/]),
	];
	aa_uqb_poss = assumeUnique(local_aa_uqb_poss);


	ID_Pin_Key_Local_Global_Possible[Template_Tag] local_aa_idpk_poss = [
		HT     : ID_Pin_Key_Local_Global_Possible(0xFF, []),
		// not all possible keys/pins may exist and files holding keys and pins can't be queried, thus always obey this rule: Assign a key/pin with ID #x to exactly a record No.#x;
		// This should allow to query numer of records and infer the available IDs now, before assigning in  local_aa_idpk_poss TODO
		AT     : ID_Pin_Key_Local_Global_Possible(0x9F, [0x81/*User's (local) Pin/1. symKey*/, 0x82/*2. local symKey*/, 0x83/*3. local symKey*/, 0x01/*Admin's (global) Pin/1. symKey*/, 0x02]),
		DST    : ID_Pin_Key_Local_Global_Possible(0xFF, [] /*[cast(ubyte)0x41, cast(ubyte)0x31, cast(ubyte)0x41, cast(ubyte)0xF1]*/ ),
		CT_asym: ID_Pin_Key_Local_Global_Possible(0xFF, []),
		CT_sym : ID_Pin_Key_Local_Global_Possible(0xFF, [0x84, 0x81, 0x82, 0x83] ),
		CCT    : ID_Pin_Key_Local_Global_Possible(0xFF, [0x84, 0x81, 0x82, 0x83] ),
	];
	aa_idpk_poss = assumeUnique(local_aa_idpk_poss);

	version(ENABLE_TOSTRING)
		writer.put("private shared static  this() was called\n\n");
}


shared static ~this() {
	BN_CTX_free(bn_ctx);
  /* Clean up */
  EVP_cleanup();
  ERR_free_strings();
	version(ENABLE_TOSTRING) 
	{
		writer.put("\nprivate shared static ~this() was called\n");
		version(Windows)
			File f = File( r"C:\test.txt", "w");
		else
			File f = File("/tmp/test.txt", "w");
		f.write(writer.data);
	}
}


/* The 2 essential exports of the 'card_driver': */

////export extern(C) __gshared const(char)* sc_module_version   = module_version.ptr; // actually not required, even if "src/libopensc/ctx.c:399" says so, but instead, the next is required
export extern(C) const(char)* sc_driver_version() {
	version(OPENSC_VERSION_LATEST) return module_version.ptr; // when private __gshared const(char[7]) 'module_version' and the libopensc.so version are the same==0.16.0
	else                           return sc_get_version;     // otherwise they fall apart, but difference may be 1 version only (only the last 2 opensc versions are supported)!
}

export extern(C) void* sc_module_init(const(char)* name) {
	static int cnt_call;
	try {
		++cnt_call;
		if (cnt_call == 1) {
			if (! rt_init())
				return null;
			version(ENABLE_TOSTRING)
				writer.formattedWrite("void* sc_module_init(const(char)* name) was called with argument name: %s and cnt_call: %s\n", name.fromStringz, cnt_call);
			return &sc_get_acos5_64_driver;
		}
		version(ENABLE_TOSTRING)
			writer.formattedWrite("void* sc_module_init(const(char)* name) was called with argument name: %s and cnt_call: %s\n", name.fromStringz, cnt_call);
		return &sc_get_acos5_64_pkcs15init_ops;
	}
	catch (Exception e) {
		return null;
	}
}

private sc_card_driver* sc_get_acos5_64_driver() {
	try {
		enforce(DES_KEY_SZ == SM_SMALL_CHALLENGE_LEN && DES_KEY_SZ == 8,
			"For some reason size [byte] of DES-block and challenge-response (card/host) is not equal and/or not 8 bytes!");
		version(ENABLE_TOSTRING)
			writer.put("sc_card_driver* sc_get_acos5_64_driver() was called\n");

		iso_ops_ptr         = sc_get_iso7816_driver.ops; // iso_ops_ptr for initialization and casual use
		acos5_64_ops        = *iso_ops_ptr; // initialize all ops with iso7816_driver's implementations

		with (acos5_64_ops) {
			match_card        = &acos5_64_match_card; // called from libopensc/card.c:186 int sc_connect_card(sc_reader_t *reader, sc_card_t **card_out) // grep -rnw -e 'acos5_\(64_\)\{0,1\}match_card' 2>/dev/null 
			acos5_64_ops.init = &acos5_64_init;       // called from libopensc/card.c:186 int sc_connect_card(sc_reader_t *reader, sc_card_t **card_out)
			finish            = &acos5_64_finish;
			read_binary       = &acos5_64_read_binary;
			erase_binary      = &acos5_64_erase_binary; // stub

			read_record       = &acos5_64_read_record;
//	iso7816_write_record,
//	iso7816_append_record,
//	iso7816_update_record,

			select_file       = &acos5_64_select_file;
			get_challenge     = &acos5_64_get_challenge;
//		verify            = null; // like in *iso_ops_ptr  this is deprecated
			logout            = &acos5_64_logout;
			set_security_env  = &acos5_64_set_security_env;
version(OPENSC_VERSION_LATEST) { // due to missing exports in 0.15.0: sc_pkcs1_strip_01_padding, sc_pkcs1_strip_02_padding
			decipher          = &acos5_64_decipher;
			compute_signature = &acos5_64_compute_signature;
}
else {
			decipher          = null; // iso_ops_ptr.compute_signature: IIRC, DOESN't work for acos5_64, at least not with key bits>2048
			compute_signature = null; // iso_ops_ptr.decipher         : IIRC, DOESN't work for acos5_64, at least not with key bits>2048
}
////			create_file       = &acos5_64_create_file;
////			delete_file       = &acos5_64_delete_file;
			list_files        = &acos5_64_list_files;
		check_sw          = &acos5_64_check_sw; // NO external use; not true: sc_check_sw calls this
			card_ctl          = &acos5_64_card_ctl;
			process_fci       = &acos5_64_process_fci;
			construct_fci     = &acos5_64_construct_fci;
			pin_cmd           = &acos5_64_pin_cmd;
//
			read_public_key   = &acos5_64_read_public_key;
		} // with (acos5_64_ops)
	}
	catch (Exception e) {
		acos5_64_ops = sc_card_operations();
	}
	acos5_64_drv.ops = &acos5_64_ops;
	return &acos5_64_drv;
}

private sc_pkcs15init_operations* sc_get_acos5_64_pkcs15init_ops() {
	try {
		version(ENABLE_TOSTRING)
			writer.put("sc_pkcs15init_operations* sc_get_acos5_64_pkcs15init_ops() was called\n");
		with (acos5_64_pkcs15init_ops) {
//			erase_card
			init_card            = &acos5_64_pkcs15_init_card;     // doesn't get called so far
//			create_dir
//			create_domain
			select_pin_reference = &acos5_64_pkcs15_select_pin_reference; // does nothing
//			create_pin
			select_key_reference = &acos5_64_pkcs15_select_key_reference; // does nothing
			create_key           = &acos5_64_pkcs15_create_key;           // does nothing
			store_key            = &acos5_64_pkcs15_store_key;            // does nothing
			generate_key         = &acos5_64_pkcs15_generate_key;
			encode_private_key   = &acos5_64_pkcs15_encode_private_key;   // does nothing
			encode_public_key    = &acos5_64_pkcs15_encode_public_key;    // does nothing
//			finalize_card
			delete_object        = &acos5_64_pkcs15_delete_object;        // does nothing
//			emu_update_dir
//			emu_update_any_df
//			emu_update_tokeninfo
//			emu_write_info
			emu_store_data       = &acos5_64_pkcs15_emu_store_data;       // does nothing ; (otherwise, after acos5_64_pkcs15_generate_key, sc_pkcs15init_store_data wouuld try to delete the publik key file, written nicely on card) 
			sanity_check         = &acos5_64_pkcs15_sanity_check;         // does nothing
		} // with (acos5_64_pkcs15init_ops)
	}
	catch (Exception e) {
		acos5_64_pkcs15init_ops = sc_pkcs15init_operations();
	}
	return &acos5_64_pkcs15init_ops;
}

/**
 * Retrieve hardware identifying serial number (6 bytes) from card and cache it
 *
 * @param card pointer to card description
 * @param serial where to store data retrieved
 * @return SC_SUCCESS if ok; else error code
 */
private int acos5_64_get_serialnr(sc_card* card, sc_serial_number* serial) {
	if (card == null || card.ctx == null)
		return SC_ERROR_INVALID_ARGUMENTS;
	int rv;
	sc_context* ctx = card.ctx;
	mixin (log!(q{"acos5_64_get_serialnr"}, q{"called"}));
	mixin log_scope_exit!("acos5_64_get_serialnr");
	scope(exit) {
		if (serial) {
			serial.value                = serial.value.init;
			serial.len                  = clamp(card.serialnr.len, 0, SC_MAX_SERIALNR);
			serial.value[0..serial.len] = card.serialnr.value[0..serial.len];
		}
		log_scope_exit_do();
	}
	try {
		if (card.type != SC_CARD_TYPE_ACOS5_64_V2 && card.type != SC_CARD_TYPE_ACOS5_64_V3)
			return rv=SC_ERROR_INS_NOT_SUPPORTED;
		/* if serial number is cached, use it */
		with (card.serialnr) {
			if (value.ptr && len==8/*6*/)
				return rv=SC_SUCCESS;
		/* not cached, retrieve serial number using GET CARD INFO, and cache serial number */
			len   = 0;
			value = value.init;
			sc_apdu apdu;
			/* Case 2 short APDU, 5 bytes: lc=0000     CLAINSP1 P2  le      ubyte[SC_MAX_APDU_BUFFER_SIZE] rbuf;*/
			bytes2apdu(ctx, cast(immutable(ubyte)[5])x"80 14 00 00  08", apdu);
			apdu.resp    = value.ptr;
			apdu.resplen = value.length;
			mixin transmit_apdu_strerror!("acos5_64_get_serialnr");
			if ((rv=transmit_apdu_strerror_do)<0) return rv;
			if (sc_check_sw(card, apdu.sw1, apdu.sw2) || apdu.resplen!=8/*6; first 6 bytes only are different in V2; using 8 because of icc.sn.length and V3*/) 
				return rv=SC_ERROR_INTERNAL;

			len = 8/*6*/;
version(ENABLE_SM) {
			card.sm_ctx.info.session.cwa.icc.sn = ub8.init;
			card.sm_ctx.info.session.cwa.icc.sn[0..len] = apdu.resp[0..len];
}
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_serialnr",
				"Serial Number of Card (EEPROM): '%s'", sc_dump_hex(value.ptr, len));
		}
		return rv=SC_SUCCESS;
	}
	catch(Throwable)
		return rv=SC_ERROR_CARD_UNRESPONSIVE;
}


/* a workaround, opensc doesn't handle ACOS keys > 2048 bit properly, so far */
private int acos5_64_get_response_large(sc_card* card, sc_apdu* apdu, size_t outlen, size_t minlen)
{
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_get_response_large"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
				"returning with: %d\n", rv);
	}

	/* this should _never_ happen */
	if (!card.ops.get_response)
		return rv=SC_ERROR_NOT_SUPPORTED;
//		LOG_TEST_RET(ctx, SC_ERROR_NOT_SUPPORTED, "no GET RESPONSE command");

	/* call GET RESPONSE until we have read all data requested or until the card retuns 0x9000,
	 * whatever happens first. */

	/* if there are already data in response append new data to the end of the buffer */
	ubyte* buf = apdu.resp + apdu.resplen;

	/* read as much data as fits in apdu.resp (i.e. min(apdu.resplen, amount of data available)). */
	size_t buflen = outlen - apdu.resplen;

	/* 0x6100 means at least 256 more bytes to read */
	size_t le = apdu.sw2 != 0 ? apdu.sw2 : 256;
	/* we try to read at least as much as bytes as promised in the response bytes */
//	minlen = crgram_len;

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
		"buflen: %lu\n", buflen);
	do {
		ubyte[256] resp;
		size_t     resp_len = le;

		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
			"le: %lu\n", le);
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
			"minlen: %lu\n", minlen);
		/* call GET RESPONSE to get more date from the card;
		 * note: GET RESPONSE returns the left amount of data (== SW2) */
		resp = resp.init;//memset(resp, 0, resp.length);
		rv = card.ops.get_response(card, &resp_len, resp.ptr);
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
			"result from card.ops.get_response(card, &resp_len, resp): %d\n", rv);
		if (rv < 0)   {
version(ENABLE_SM)
{
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
				"Here I am");
			if (resp_len)   {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
					"SM response data %s", sc_dump_hex(resp.ptr, resp_len));
				sc_sm_update_apdu_response(card, resp.ptr, resp_len, rv, apdu);
			}
}
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
				"GET RESPONSE error");
			return rv;
		}

		le = resp_len;
		/* copy as much as will fit in requested buffer */
		if (buflen < le)
			le = buflen;

		memcpy(buf, resp.ptr, le);
		buf    += le;
		buflen -= le;
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
			"buflen: %lu\n", buflen);

		/* we have all the data the caller requested even if the card has more data */
		if (buflen == 0)
			break;

		minlen = (minlen>le ? minlen - le :  0);
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
			"minlen: %lu\n", minlen);
		if (rv != 0)
			le = minlen = rv;
		else
			/* if the card has returned 0x9000 but we still expect data ask for more
			 * until we have read enough bytes */
			le = minlen;
	} while (rv != 0 || minlen != 0);
	if (rv < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_response_large",
			"cannot get all data with 'GET RESPONSE'");
		return rv;
	}

	/* we've read all data, let's return 0x9000 */
	apdu.resplen = buf - apdu.resp;
	apdu.sw1 = 0x90;
	apdu.sw2 = 0x00;

	return rv=SC_SUCCESS;
}
version(OPENSC_VERSION_LATEST) {}
else // for some reason, this usefull function is not exported from libopensc's version 0.15.0
private int missingExport_match_atr_table(sc_context* ctx, sc_atr_table* table, sc_atr* atr)
{ // c source function 'match_atr_table' copied, translated to D
	ubyte* card_atr_bin;
	size_t card_atr_bin_len;
	char[3 * SC_MAX_ATR_SIZE] card_atr_hex;
	size_t                    card_atr_hex_len;
	uint i = 0;

	if (ctx == null || table == null || atr == null)
		return -1;
	card_atr_bin     = atr.value.ptr;
	card_atr_bin_len = atr.len;
	sc_bin_to_hex(card_atr_bin, card_atr_bin_len, card_atr_hex.ptr, card_atr_hex.sizeof, ':');
	card_atr_hex_len = strlen(card_atr_hex.ptr);

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "missingExport_match_atr_table", "ATR     : %s", card_atr_hex.ptr);

	for (i = 0; table[i].atr != null; i++) {
		const(char)* tatr = table[i].atr;
		const(char)* matr = table[i].atrmask;
		size_t tatr_len = strlen(tatr);
		ubyte[SC_MAX_ATR_SIZE] mbin, tbin;
		size_t mbin_len, tbin_len, s, matr_len;
		size_t fix_hex_len = card_atr_hex_len;
		size_t fix_bin_len = card_atr_bin_len;

		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "missingExport_match_atr_table", "ATR try : %s", tatr);

		if (tatr_len != fix_hex_len) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "missingExport_match_atr_table", "ignored - wrong length");
			continue;
		}
		if (matr != null) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "missingExport_match_atr_table", "ATR mask: %s", matr);

			matr_len = strlen(matr);
			if (tatr_len != matr_len)
				continue;
			tbin_len = tbin.sizeof;
			sc_hex_to_bin(tatr, tbin.ptr, &tbin_len);
			mbin_len = mbin.sizeof;
			sc_hex_to_bin(matr, mbin.ptr, &mbin_len);
			if (mbin_len != fix_bin_len) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "missingExport_match_atr_table",
					"length of atr and atr mask do not match - ignored: %s - %s", tatr, matr);
				continue;
			}
			for (s = 0; s < tbin_len; s++) {
				/* reduce tatr with mask */
				tbin[s] = (tbin[s] & mbin[s]);
				/* create copy of card_atr_bin masked) */
				mbin[s] = (card_atr_bin[s] & mbin[s]);
			}
			if (memcmp(tbin.ptr, mbin.ptr, tbin_len) != 0)
				continue;
		}
		else {
			if (!equal(fromStringz(tatr), card_atr_hex[])) //(strncasecmp(tatr, card_atr_hex, tatr_len) != 0)
				continue;
		}
		return i;
	}
	return -1;
}


private int acos5_64_match_card_checks(sc_card *card) { // regular return value: 0==SUCCESS
	int rv = SC_ERROR_INVALID_CARD;
	sc_context* ctx = card.ctx;
	mixin (log!(q{"acos5_64_match_card_checks"}, q{"called"}));
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_match_card_checks",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_match_card_checks",
				"returning with: %d\n", rv);
	}

	/* call 7.3.1. Get Card Info Identify Self. SW1 SW2 = 95 40h for ACOS5-64 ; make shure we really deal with a ACOS5-64 card */
	/* brand-new ACS ACOS5-64 V3.00 check: send the following sequence of bytes (APDU command as hex) to Your token with a tool like gscriptor (in window "Script") and run:
80140500

Probably the answer is: Received: 95 40, which is expected and okay (though gscriptor believes it is an error)
If the answer is different, You will have to add an "else if" in function acos5_64_check_sw too:
	else if (sw1 == 0x??U && sw2 == 0x??U) // this is a response to "Identify Self" and is okay for Version ACS ACOS5-64 v3.00/no error
		return rv=SC_SUCCESS;
	*/
	sc_apdu apdu;
	sc_format_apdu(card, &apdu, SC_APDU_CASE_1, 0x14, 0x05, 0x00); 
	apdu.cla = 0x80;

	mixin transmit_apdu_strerror!("acos5_64_match_card_checks");
	if ((rv=transmit_apdu_strerror_do) < 0) return rv;
	if ((rv=acos5_64_check_sw(card, apdu.sw1, apdu.sw2)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_match_card_checks",
			"SW1SW2 doesn't match 0x9540: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}

	/* call 7.3.1. Get Card Info Card OS Version */
	/* brand-new ACS ACOS5-64 V3.00 check: send the following sequence of bytes (APDU command as hex) to Your token with a tool like gscriptor (in window "Script") and run:
8014060008

"41434F5305 02 00 40"
Probably the answer is: Received: 41 43 4F 53 05 02 00 40 90 00, which is expected and okay (though gscriptor believes it is an error)
If the answer is different, You will have to add an "else if" in function acos5_64_check_sw too:
	else if (sw1 == 0x??U && sw2 == 0x??U) // this is a response to "Identify Self" and is okay for Version ACS ACOS5-64 v3.00/no error
		return rv=SC_SUCCESS;
	*/
	immutable(ubyte)[8][2] vbuf = [ cast(immutable(ubyte)[8]) x"41434F5305 02 00 40",  // "ACOS 0x05 ...", major vers.=2,   minor=0,   0x40 kBytes user EEPROM capacity
	                                cast(immutable(ubyte)[8]) x"41434F5305 03 00 40"]; // "ACOS 0x05 ...", major vers.=3,   minor=0,   0x40 kBytes user EEPROM capacity
	ub8 rbuf;
	apdu = sc_apdu(); // apdu = apdu.init;
	sc_format_apdu(card, &apdu, SC_APDU_CASE_2, 0x14, 0x06, 0x00);
	with (apdu) {
		cla          = 0x80;
		le = resplen = rbuf.sizeof;
		resp         = rbuf.ptr;
	}

	if ((rv=transmit_apdu_strerror_do) < 0) return rv;
	if (apdu.sw1 != 0x90 || apdu.sw2 != 0x00)
		return rv=SC_ERROR_INTERNAL;
	// equality of vbuf_2 and rbuf ==> 0==SC_SUCCESS, 	inequality==> 1*SC_ERROR_NO_CARD_SUPPORT
	if ((rv=SC_ERROR_INVALID_CARD* !equal(rbuf[], vbuf[card.type-SC_CARD_TYPE_ACOS5_64_V2][])) < 0) { // equal(rbuf[], vbuf_2[])
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_match_card_checks",
			"Card OS Version doesn't match: major(%d), minor(%d), EEPROM user capacity in kilobytes (0x%02X)\n", rbuf[5], rbuf[6], rbuf[7]);
		return rv;
	}
	card.version_.hw_major = rbuf[5];
	card.version_.hw_minor = rbuf[6];

	return rv;
}

/**
 * Check if provided card can be handled.
 *
 * Called in sc_connect_card().  Must return 1, if the current
 * card can be handled with this driver, or 0 otherwise.  ATR field
 * of the sc_card struct is filled in before calling this function.
 *
 * do not declare static, if pkcs15-acos5_64 module should be necessary
 *
 * @param card Pointer to card structure
 * @returns 1 on card matched, 0 if no match (or error)
 *
 * Returning 'no match' still doesn't stop opensc-pkcs11 using this driver, when forced to use acos5_64
 * Thus for case "card not matched", another 'killer argument': set card.type to impossible one and rule out in acos5_64_init
 */
private extern(C) int acos5_64_match_card(sc_card *card) { // irregular/special return value: 0==FAILURE
	int rv;
	sc_context* ctx = card.ctx;
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_match_card",
		"try to match card with ATR %s", sc_dump_hex(card.atr.value.ptr, card.atr.len));
	scope(exit) {
		if (rv == 0) { // FAILURE, then stall acos5_64_init !!! (a FAILURE in 'match_card' is skipped e.g. when force_card_driver is active, but a FAILURE in 'init' is adhered to)
			card.type = -1;
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_match_card",
				"card not matched");
		}
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_match_card",
				"card matched (%s)", acos5_64_atrs[0].name);
	}

version(OPENSC_VERSION_LATEST) {
	if ((rv=             _sc_match_atr(card, acos5_64_atrs.ptr, &card.type)) < 0)
		return rv=0;
}
else { // for some reason, this usefull function is not exported from libopensc's version 0.15.0
	int missingExport_sc_match_atr(sc_card* card, sc_atr_table* table, int* type_out)
	{ // c source _sc_match_atr copied, translated to D
		int res;

		if (card == null)
			return -1;
		res = missingExport_match_atr_table(card.ctx, table, &card.atr);
		if (res < 0)
			return res;
		if (type_out != null)
			*type_out = table[res].type;
		return res;
	}
	if ((rv=missingExport_sc_match_atr(card, acos5_64_atrs.ptr, &card.type)) < 0)
		return rv=0;
}
	return rv=!cast(bool)acos5_64_match_card_checks(card);
}


void handleErrors(int i) {
	version(ENABLE_TOSTRING) {
		writer.put("handleErrors(int i) called\n");
		writer.formattedWrite("%s", i);
	}
}

int encrypt_algo(in uba plaintext,  in ubyte* key, in ubyte* iv, ubyte* ciphertext, const(EVP_CIPHER)* algo, bool pad=true,
	uint macOut_len = DES_KEY_SZ /* this is for CMAC only and may be given to reduce number of MAC bytes (starting at last ub8 block) written to ciphertext*/) {
// https://wiki.openssl.org/index.php/EVP_Symmetric_Encryption_and_Decryption
// http://etutorials.org/Programming/secure+programming/Chapter+5.+Symmetric+Encryption/5.17+Performing+Block+Cipher+Setup+for+CBC+CFB+OFB+and+ECB+Modes+in+OpenSSL/
	EVP_CIPHER_CTX* evp_ctx;

	int len;

	int ciphertext_len;

	/* Create and initialise the context */
	if ((evp_ctx = EVP_CIPHER_CTX_new()) == null)
		handleErrors(1);

	/* Initialise the encryption operation. IMPORTANT - ensure you use a key
	 * and IV size appropriate for your cipher
	 * In this example we are using 256 bit AES (i.e. a 256 bit key). The
	 * IV size for *most* modes is the same as the block size. For AES this
	 * is 128 bits */
	if (1 != EVP_EncryptInit_ex(evp_ctx, algo, null, key, iv))
		handleErrors(2);

	if (!pad)
		EVP_CIPHER_CTX_set_padding(evp_ctx, 0);

	/* Provide the message to be encrypted, and obtain the encrypted output.
	 * EVP_EncryptUpdate can be called multiple times if necessary
	 */
	if (1 != EVP_EncryptUpdate(evp_ctx, ciphertext, &len, plaintext.ptr, cast(int)plaintext.length))
		handleErrors(3);
	ciphertext_len = len;

	/* Finalise the encryption. Further ciphertext bytes may be written at
	 * this stage.
	 */
	if (1 != EVP_EncryptFinal_ex(evp_ctx, ciphertext + len, &len))
		handleErrors(4);
	ciphertext_len += len;

	/* Clean up */
	EVP_CIPHER_CTX_free(evp_ctx);

	return ciphertext_len;
}

int decrypt_algo(in uba ciphertext, in ubyte* key, in ubyte* iv, ubyte* plaintext,  const(EVP_CIPHER)* algo, bool pad=true) {
	EVP_CIPHER_CTX* evp_ctx;

	int len;

	int plaintext_len;

	/* Create and initialise the context */
//	if (!(evp_ctx = EVP_CIPHER_CTX_new()))
	if ((evp_ctx = EVP_CIPHER_CTX_new()) == null)
		handleErrors(11);

	/* Initialise the decryption operation. IMPORTANT - ensure you use a key
	 * and IV size appropriate for your cipher
	 * In this example we are using 256 bit AES (i.e. a 256 bit key). The
	 * IV size for *most* modes is the same as the block size. For AES this
	 * is 128 bits */
	if (1 != EVP_DecryptInit_ex(evp_ctx, algo, /*EVP_aes_256_cbc()*/ null, key, iv))
		handleErrors(12);

	if (!pad)
		EVP_CIPHER_CTX_set_padding(evp_ctx, 0);

	/* Provide the message to be decrypted, and obtain the plaintext output.
	 * EVP_DecryptUpdate can be called multiple times if necessary
	 */
	if (1 != EVP_DecryptUpdate(evp_ctx, plaintext, &len, ciphertext.ptr, cast(int)ciphertext.length))
		handleErrors(13);
	plaintext_len = len;

	/* Finalizee the decryption. Further plaintext bytes may be written at
	 * this stage.
	 */
	if (1 != EVP_DecryptFinal_ex(evp_ctx, plaintext + len, &len))
		handleErrors(14);
	plaintext_len += len;

	/* Clean up */
	EVP_CIPHER_CTX_free(evp_ctx);

	return plaintext_len;
}

/** swallow all ciphertext except last DES_KEY_SZ-sized block, ouput first out_len bytes of this
 * CBC-MAC  based on des_ede3_cbc/des_ede_cbc, 24/16 byte key,
 * adapted for convinience as ACOS5_64 takes a 4 byte out_len MAC only		
 * not strictly necessary, if des3_encrypt_cbc is applied correctly (last 8 byte block !); advantage: less (fixed) memory alloc; simple building block
 */
int encrypt_algo_cbc_mac(in uba plaintext, in ubyte* key, in ubyte* iv, ubyte* ciphertext, const(EVP_CIPHER)* algo, bool pad=true, uint dac=DAC, uint out_len = DES_KEY_SZ)
{
	DES_cblock    res    = iv[0..8];
	ub24 /*DES_cblock*/ iv2; 
	const(ubyte)* in_p   = plaintext.ptr;
	size_t        in_len = plaintext.length;
	int           rv     = SC_ERROR_SM_INVALID_CHECKSUM;

	if (/*input-*/in_len==0 || in_len % DES_KEY_SZ || out_len>8 || !canFind([EVP_des_ede3_cbc, EVP_des_ede_cbc], algo))
		return rv;

	while (in_len>0) {
		iv2 = ub24.init;
		iv2[0..8] = res[];
		if ((rv=
			encrypt_algo(in_p[0..8], key, iv2.ptr, res.ptr, algo, false))
			!= DES_KEY_SZ)
			return rv;
		in_p   += DES_KEY_SZ;
		in_len -= DES_KEY_SZ;
	}
	ciphertext[0..out_len] = res[0..out_len];
	return out_len;
}

unittest {
	version(SESSIONKEYSIZE24) {
		ub24 random_bytes;
		assert(1==RAND_bytes(random_bytes.ptr, random_bytes.length));
		immutable(ub24) key = random_bytes[];
	}
	else {
		ub16 random_bytes;
		assert(1==RAND_bytes(random_bytes.ptr, random_bytes.length));
		immutable(ub16) key = random_bytes[];
	}

	immutable(ubyte[72]) plaintext_pre = representation("###Victor jagt zwölf Boxkämpfer quer über den großen Sylter Deich###")[]; // includes 4 2-byte german unicode code points 
	ubyte[72]            ciphertext;
	ubyte[72]            plaintext_post;
	ub8                  mac;
	ub8                  iv; // for TDES usage only
	int                  rv;
//	writefln("plaintext_pre:  0x [%(%02x %)]", plaintext_pre);
	assert(plaintext_pre.length==encrypt_algo(plaintext_pre,  key.ptr, iv.ptr, ciphertext.ptr,     cipher_TDES[CBC], false));
	assert(plaintext_pre.length==decrypt_algo(ciphertext,     key.ptr, iv.ptr, plaintext_post.ptr, cipher_TDES[CBC], false));
	assert(equal(plaintext_pre[], plaintext_post[]));
//	writefln("plaintext_post: 0x [%(%02x %)]", plaintext_post);
	assert(  mac.length==encrypt_algo_cbc_mac(plaintext_pre,  key.ptr, iv.ptr, mac.ptr,            cipher_TDES[DAC], false, DAC));
//	writefln("ciphertext:     0x [%(%02x %)]", ciphertext);
//	writefln("mac:            0x [                                                                                                                                                                                                %(%02x %)]", mac);
	mac = mac.init;
	iv = [1,2,3,4,5,6,7,8];
	assert(           4==encrypt_algo_cbc_mac(plaintext_pre,  key.ptr, iv.ptr, mac.ptr,            cipher_TDES[DAC], false, DAC, 4));
//	writefln("mac4:           0x [%(%02x %)]", mac);
//	writeln("PASSED: encrypt_algo, decrypt_algo, encrypt_algo_cbc_mac, without padding");
}

private int check_weak_DES_key(sc_card *card, in uba key) {
	return SC_SUCCESS;
}


private extern(C) int acos5_64_init(sc_card *card) {
	sc_context* ctx = card.ctx;
	int         rv  = SC_ERROR_INVALID_CARD; // SC_ERROR_NO_CARD_SUPPORT
	sc_apdu apdu;
	mixin (log!(q{"acos5_64_init"}, q{"called"}));
	mixin transmit_apdu_strerror!("acos5_64_init");
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init",
				"returning with: %d\n", rv);
	}

	int ii;
	for (ii=0; acos5_64_atrs[ii].atr; ++ii)
		if (card.type  == acos5_64_atrs[ii].type)
			break;

	// if no card.type match in previous for loop, ii is at list end marker all zero
	if (!acos5_64_atrs[ii].atr) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init", "about to stall this driver (some matching problem)\n");
		return rv=SC_ERROR_INVALID_CARD;
	}

	if (card.type==SC_CARD_TYPE_ACOS5_64_V3) {
		// the Operation Mode Byte Setting retrievable from card and the dlang version specifier must match
		//sc_apdu apdu; //                         CLAINSP1 P2
		bytes2apdu(ctx, cast(immutable(ubyte)[4])x"80 14 09 00", apdu);
		if ((rv=transmit_apdu_strerror_do())<0) return rv;
		if (apdu.sw1 != 0x95 || !canFind([0U, 1U, 2U, 16U], apdu.sw2)) // this is a response to "Identify Self" and is okay for Version ACS ACOS5-64 v2.00/no error
			return rv=SC_ERROR_INVALID_CARD;
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init", "the Operation Mode Byte is set to: %i (ACOSMODE_V3_FIPS_140_2L3(0),'Emulated 32K Mode'(1), ACOSMODE_V2(2), ACOSMODE_V3_NSH_1(16))\n", apdu.sw2);
version(ACOSMODE_V2) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init", "the Operation Mode Byte set doesn't match 2 (version identifier ACOSMODE_V2, this code was compiled with)\n");
		if (apdu.sw2 !=  2) return rv=SC_ERROR_INVALID_CARD;
}
else version(ACOSMODE_V3_FIPS_140_2L3) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init", "the Operation Mode Byte set doesn't match 0 (version identifier ACOSMODE_V3_FIPS_140_2L3, this code was compiled with)\n");
		if (apdu.sw2 !=  0) return rv=SC_ERROR_INVALID_CARD;
}
else version(ACOSMODE_V3_NSH_1) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init", "the Operation Mode Byte set doesn't match 16 (version identifier ACOSMODE_V3_NSH_1, this code was compiled with)\n");
		if (apdu.sw2 != 16) return rv=SC_ERROR_INVALID_CARD;
}
else {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init", "the Operation Mode Byte set doesn't match 16 (version identifier ACOSMODE_V3_NSH_1, this code was compiled with)\n");
		return rv=SC_ERROR_INVALID_CARD;
}
/*		
Operation Mode											Value
FIPS 140-2 Level 3–Compliant Mode		00h
Emulated 32K Mode										01h
64K Mode														02h
NSH-1 Mode													10h
*/
version(ACOSMODE_V3_FIPS_140_2L3) {
		apdu = sc_apdu(); // check FIPS 140_2L3 compliance: card file system and settings
		bytes2apdu(ctx, cast(immutable(ubyte)[4])x"80 14 0A 00", apdu);
		if ((rv=transmit_apdu_strerror_do())<0) return rv;
		if ((rv=sc_check_sw(card, apdu.sw1, apdu.sw2))<0) return rv;
}
	}
	else {
version(ACOSMODE_V2) {}
else return rv=SC_ERROR_INVALID_CARD;
	}

	acos5_64_private_data* private_data;

version(none) // FIXME activate this again for Posix, investigate for Windows, when debugging is done
{
version(Posix)
{
	import core.sys.posix.sys.resource : RLIMIT_CORE, rlimit, setrlimit;
	rlimit core_limits; // = rlimit(0, 0);
	if ((rv=setrlimit(RLIMIT_CORE, &core_limits)) != 0) { // inhibit core dumps, https://download.libsodium.org/doc/helpers/memory_management.html
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init", "Setting rlimit failed !\n");
		return rv;
	}
}
}

	private_data = cast(acos5_64_private_data*) malloc(acos5_64_private_data.sizeof);
	if (private_data == null)
		return rv=SC_ERROR_MEMORY_FAILURE;
version(USE_SODIUM)
{
	synchronized { // check for need to synchronize sinceversion 1.0.11
		if (sodium_init == -1) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init", "sodium_init() returned indicating a failure)\n");
			return rv=SC_ERROR_CARD_CMD_FAILED;
		}
	}
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init",
		"This module initialized libsodium version: %s\n", sodium_version_string);
////	private_data = cast(acos5_64_private_data*) sodium_malloc(acos5_64_private_data.sizeof);
////	if (private_data == null)
////		return rv=SC_ERROR_MEMORY_FAILURE;
////	if ((rv=sodium_mlock(private_data, acos5_64_private_data.sizeof)) < 0) // inhibit swapping sensitive data to disk
////		return rv;
////	if ((rv=sodium_mprotect_noaccess(private_data)) <0)                    // inhibit access to private_data other than controled one by this library
////		return rv;
} // version(USE_SODIUM)

	c_ulong algoflags =   SC_ALGORITHM_ONBOARD_KEY_GEN   // 0x8000_0000
						| SC_ALGORITHM_RSA_RAW           // 0x0000_0001  /* RSA raw support */
						| SC_ALGORITHM_RSA_PAD_NONE //   CHANGED, but makes no difference; it means: the card/driver doesn't do the padding, but opensc does it
						| SC_ALGORITHM_RSA_HASH_SHA1     // sign: the driver will not use RSA raw  0x0000_0020
						| SC_ALGORITHM_RSA_HASH_SHA256   // sign: the driver will not use RSA raw  0x0000_0200
				;                       // 0x8000_0231

	with (*card) {
		// SC_CARD_CAP_USE_FCI_AC : There is only 1 usage in sc_pkcs15init_authenticate pkcs15init/pkcs15-lib.c:3492
		caps =  SC_CARD_CAP_RNG
					| SC_CARD_CAP_USE_FCI_AC;
		cla           = 0x00;  // int      default APDU class (interindustry)
		max_send_size = SC_READER_SHORT_APDU_MAX_SEND_SIZE; //0x0FF; // 0x0FFFF for usb-reader, 0x0FF for chip/card;  Max Lc supported by the card
		max_recv_size = SC_READER_SHORT_APDU_MAX_RECV_SIZE; //0x100; // 0x10000 for usb-reader, 0x100 for chip/card;  Max Le supported by the card, decipher (in chaining mode) with a 4096-bit key returns 2 chunks of 256 bytes each !!

		int missingExport_sc_card_add_algorithm(sc_card* card, const(sc_algorithm_info)* info) {
			sc_algorithm_info* p;

			assert(info != null);
			p = cast(sc_algorithm_info*) realloc(card.algorithms, (card.algorithm_count + 1) * sc_algorithm_info.sizeof);
			if (!p) {
				if (card.algorithms)
					free(card.algorithms);
				card.algorithms = null;
				card.algorithm_count = 0;
				return SC_ERROR_OUT_OF_MEMORY;
			}
			card.algorithms = p;
			p += card.algorithm_count;
			card.algorithm_count++;
			*p = *info;
			return SC_SUCCESS;
		}

version(OPENSC_VERSION_LATEST) {}
else
		int missingExport_sc_card_add_rsa_alg(sc_card* card, uint key_length, c_ulong flags, c_ulong exponent)
		{ // same as in opensc, but combined with _sc_card_add_algorithm; both are not exported by libopensc
			sc_algorithm_info info;
			info.algorithm = SC_ALGORITHM_RSA;
			info.key_length = key_length;
			info.flags = cast(uint)flags;
			info.u._rsa.exponent = exponent;
			sc_algorithm_info* p = cast(sc_algorithm_info*) realloc(card.algorithms, (card.algorithm_count + 1) * info.sizeof);
			if (!p) {
				if (card.algorithms)
					free(card.algorithms);
				card.algorithms = null;
				card.algorithm_count = 0;
				return SC_ERROR_OUT_OF_MEMORY;
			}
			card.algorithms = p;
			p += card.algorithm_count;
			card.algorithm_count++;
			*p = info;
			return SC_SUCCESS;
		}

version(ACOSMODE_V3_FIPS_140_2L3)
	immutable uint key_len_from = 0x800, key_len_to = 0x0C00, key_len_step = 0x400; 
else
	immutable uint key_len_from = 0x200, key_len_to = 0x1000, key_len_step = 0x100; 

		for (uint key_len = key_len_from; key_len <= key_len_to; key_len += key_len_step) {
version(OPENSC_VERSION_LATEST)
										_sc_card_add_rsa_alg(card, key_len, algoflags, 0x10001);
else
			 missingExport_sc_card_add_rsa_alg(card, key_len, algoflags, 0x10001);
		}
		drv_data = private_data; // void*, null if NOT version=USE_SODIUM, garbage collector (GC) not involved
		max_pin_len = 8; // int
		with (cache) { // sc_card_cache
		  // on reset, MF is automatically selected
			current_df = sc_file_new;
			if (current_df == null)
				return rv=SC_ERROR_MEMORY_FAILURE;

			current_df.path = MF_path; // TODO do more than .path, e.g. ubyte* sec_attr, sc_acl_entry[SC_MAX_AC_OPS]* acl  etc.
			valid = 1; // int
		} // with (cache)
		if ((rv=acos5_64_get_serialnr(card, null)) < 0) { // card.serialnr will be stored/cached
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init",
				"Retrieving ICC serial# failed: %d (%s)\n", rv, sc_strerror(rv));
			return rv;
		}

		with (version_) { // sc_version
			fw_major = hw_major; // ubyte
			fw_minor = hw_minor; // ubyte
		}
version(ENABLE_SM)
{
		with (sm_ctx) { // sm_context
			info.serialnr                       = card.serialnr;
			with (card.sm_ctx.info) {
				config_section                    = "acos5_64_sm";
				card_type                         = card.type; 
				sm_type                           = SM_TYPE_CWA14890;
version(SESSIONKEYSIZE24)
				session.cwa.params.crt_at.refs[0] = 0x82; // this is the selection of keyset_... ...02_... to be used !!! Currently 24 byte keys (generate 24 byte session keys)
else
				session.cwa.params.crt_at.refs[0] = 0x81; // this is the selection of keyset_... ...01_... to be used !!!           16 byte keys (generate 16 byte session keys)

				current_aid                       = sc_aid(); // ubyte[SC_MAX_AID_SIZE==16] value; size_t len;
				current_aid.len                   = SC_MAX_AID_SIZE; // = "ACOSPKCS-15v1.00".length
				current_aid.value                 = representation("ACOSPKCS-15v1.00")[];
			}
			ops.open         = &sm_acos5_64_card_open;
			ops.close        = &sm_acos5_64_card_close;
			ops.get_sm_apdu  = &sm_acos5_64_card_get_sm_apdu;
			ops.free_sm_apdu = &sm_acos5_64_card_free_sm_apdu;
		} // with (sm_ctx)
} // version(ENABLE_SM)
	} // with (*card)

version(ENABLE_ACOS5_64_UI) {
	/* read environment from configuration file */
	if ((rv=acos5_64_get_environment(card, &(get_acos5_64_ui_ctx(card)))) != SC_SUCCESS) {
		free(card.drv_data);
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_init", "Failure reading acos5_64 environment.");
		return rv;
	}
}

	return rv=SC_SUCCESS;
} // acos5_64_init

/**
 * De-initialization routine.
 *
 * Called when the card object is being freed.  finish() has to
 * deallocate all possible private data.
 *
 * @param card Pointer to card driver data structure
 * @return SC_SUCCESS if ok; else error code
 */
private extern(C) int acos5_64_finish(sc_card *card) {
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_finish"}, q{"called"})); //
	mixin log_scope_exit!("acos5_64_finish"); 
	scope(exit) {
		log_scope_exit_do();
////		version(Windows) {} else rt_term();
	}

////version(USE_SODIUM)
////{
////	rv = sodium_mprotect_readwrite(card.drv_data);
/*
	acos5_64_private_data* private_data = cast(acos5_64_private_data*) card.drv_data;
	acos5_64_se_info*      se_info      = private_data.se_info;
	acos5_64_se_info*      next;

	while (se_info)   {
		if (se_info.df)
			sc_file_free(se_info.df);
		next = se_info.next;
		free(se_info);
		se_info = next;
	}
*/
////	sodium_munlock(card.drv_data, acos5_64_private_data.sizeof);
////	sodium_free(card.drv_data);
	free(card.drv_data);
	card.drv_data = null;
	return rv=SC_SUCCESS;
}

private extern(C) int acos5_64_read_binary(sc_card* card, uint idxORrec_nr, ubyte* buf, size_t count, c_ulong flags)
{ // this is currently only a pass-through-function to get logging
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_read_binary"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_read_binary",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_read_binary",
				"returning with: %d\n", rv);
	}
	return rv=iso_ops_ptr.read_binary(card, idxORrec_nr, buf, count, flags);
}


private extern(C) int acos5_64_erase_binary(sc_card *card, uint idx, size_t count, c_ulong flags)
{
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_NOT_SUPPORTED;
	mixin (log!(q{"acos5_64_erase_binary"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_erase_binary",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_erase_binary",
				"returning with: %d\n", rv);
	}
	return rv;
}

/**
opensc-tool doesn't communicate the length of data to be read, only the length of accepting buffer is specified (ubyte[256] buf is sufficient, as acos MRL is 255)
1 trial and error is sufficient, asking for 0xFF bytes: In the likely case of wrong length, acos will respond with 6C XXh where XXh is the maximum bytes
available in the record and opensc automatically issues the corrected APDU once more
*/
private extern(C) int acos5_64_read_record(sc_card* card, uint rec_nr,
	ubyte* buf, size_t buf_len, c_ulong flags) {
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_read_record"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_read_record",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_read_record",
				"returning with: %d\n", rv);
	}
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_read_record",
		"called with rec_nr(%u), buf_len(%lu), flags(%lu)\n", rec_nr, buf_len, flags);

	sc_apdu apdu;
	sc_format_apdu(card, &apdu, SC_APDU_CASE_2, 0xB2, 1+rec_nr, 0x04); // opensc/acos indexing differ by 1

	with (apdu) {
		le = 0xFF;
		resplen = buf_len;
		resp = buf;
	}
	mixin transmit_apdu!("acos5_64_read_record");  if ((rv=transmit_apdu_do) < 0) return rv;

	if (apdu.resplen == 0)
		return rv=sc_check_sw(card, apdu.sw1, apdu.sw2);

	return rv=cast(int)apdu.resplen;
}

private int acos5_64_select_file_by_path(sc_card* card, const(sc_path) *in_path, sc_file **file_out, bool force_select=false)
{
	size_t          in_len = in_path.len;
	const(ubyte) *  in_pos = in_path.value.ptr;
	ubyte*          p = null;
	uba             p_arr;
	int  /*result = -1,*/ in_path_complete = 1, diff = 2;
	sc_path path_substitute;
	sc_path* p_path = cast(sc_path*)in_path;  /*pointing to in_path or path_substitute*/

	uint file_type = SC_FILE_TYPE_WORKING_EF;
	bool force_select_current;
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_select_file_by_path"}, q{"called"}));
	scope(exit) {
		if (rv <= 0) {
			if (rv == 0 && file_out && *file_out == null /* are there any cases where *file_out != null ? */) {
				*file_out = sc_file_new();
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file_by_path",
					"sc_file_new() was called\n");
			}
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file_by_path",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		}
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file_by_path",
				"returning with: %d\n", rv);
	}

	/* Check parameters. */
	with (*in_path) {
		if (len % 2 != 0 || len < 2) {
			return rv=SC_ERROR_INVALID_ARGUMENTS;
		}
		if (type==SC_PATH_TYPE_FROM_CURRENT || type==SC_PATH_TYPE_PARENT)
			return rv=SC_ERROR_UNKNOWN;
	}

	if (!sc_compare_path_prefix(&MF_path, in_path)) /*incomplete path given for in_path */
		in_path_complete = 0;
	with (*in_path) with (card.cache)  sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file_by_path",
		"starting with card->cache.current_df->path=%s, card->cache.valid=%d, searching: path->len=%lu, path->index=%d, path->count=%d, path->type=%d, file_out=%p",
			sc_print_path(&current_df.path), valid, len, index, count, type, file_out);
	if (card.cache.valid) {
		if (!in_path_complete) {
			p_arr = find(card.cache.current_df.path.value[], take(in_path.value[], 2));
			p = p_arr.empty? null : p_arr.ptr;
			if (p && ((p-card.cache.current_df.path.value.ptr) % 2 == 0)) {
				sc_path path_prefix;
				memset(&path_prefix, 0, sc_path.sizeof);
				path_prefix.len = p-card.cache.current_df.path.value.ptr;
				memcpy(&path_prefix, &card.cache.current_df.path, path_prefix.len);
				sc_concatenate_path(&path_substitute, &path_prefix, in_path);
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file_by_path",
					"starting with path_substitute=%s (memmem)\n", sc_print_path(&path_substitute));
				p_path = &path_substitute;
				in_len = path_substitute.len;
				in_pos = path_substitute.value.ptr;
			}
			/*if card->cache.current_df->path==MF_path and card->cache.valid and in_path->len ==2*/
			else if (sc_compare_path(&card.cache.current_df.path, &MF_path) /*&& in_path->len == 2*/) {
				sc_concatenate_path(&path_substitute, &MF_path, in_path);
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file_by_path",
					"starting with path_substitute=%s (MFprefix)\n", sc_print_path(&path_substitute));
				p_path = &path_substitute;
				in_len = path_substitute.len;
				in_pos = path_substitute.value.ptr;
			}
		}

		with (card.cache) {
		/* Don't need to select if it's other than MF_path ? */
			if (sc_compare_path(&current_df.path, p_path) &&
				!sc_compare_path(&current_df.path, &MF_path)) { /*check current DF*/
				if (!force_select) {
					sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file_by_path",
						"Don't need to select ! ending with card->cache.current_df->path=%s, card->cache.valid=%d",	sc_print_path(&current_df.path), valid);
					rv=SC_SUCCESS;
					return rv;
				}
				else {
					force_select_current = true;
					sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file_by_path",
						"Don't need to select (but we are forced to select, maybe in order to clear accumulated MSE-CRTs!)");
				}
			}
			/* shorten the path based on card->cache.current_df->path */
			if (in_len>2) {
				if (force_select_current) {
					in_pos += in_len-2;
					in_len = 2;
				}
				else if (sc_compare_path_prefix(&current_df.path, p_path)) { /* check current DF's children*/
					in_len -= current_df.path.len;
					in_pos += current_df.path.len;
				}
				else if (current_df.path.len > 2) { /* check current DF's parent and it's children*/
					sc_path path_parent;
					sc_path_set(&path_parent, /*SC_PATH_TYPE.*/SC_PATH_TYPE_FILE_ID, current_df.path.value.ptr, current_df.path.len-2, 0, -1);
					if ( sc_compare_path(&path_parent, p_path) ||
							(sc_compare_path_prefix(&path_parent, p_path) && current_df.path.len==in_len)) {
						in_pos += in_len-2;
						in_len = 2;
					}
				}
				/*check MF's children */
				else if (sc_compare_path_prefix(&MF_path, p_path) && 4==in_len) {
					in_pos += in_len-2;
					in_len = 2;
				}
			}
		} // with (card.cache)
	} // if (card.cache.valid)

	if (cast(ptrdiff_t)in_len<=0 || in_len%2)
		return rv=SC_ERROR_INVALID_ARGUMENTS;
	/* process path components
		 iso_ops_ptr.select_file can do it, iff it get's a special set of arguments */
	sc_path path;
	path.type = /*SC_PATH_TYPE.*/SC_PATH_TYPE_FILE_ID;
	path.len = 2;		/* one path component at a time */
	do {
		if (in_len>=4) {
			sc_apdu apdu;
			sc_format_apdu(card, &apdu, SC_APDU_CASE_3_SHORT, 0xA4, 0, 0);
			with (apdu) {
				lc = datalen = 2;
				data = /*cast(ubyte*)*/in_pos;
				flags |= SC_APDU_FLAGS_NO_GET_RESP; // prevent get_response and process_fci
			}
			rv = sc_transmit_apdu(card, &apdu) || apdu.sw1 != 0x61;
		}
		else if (in_len==2 || rv) {
			path.value[0..2] = in_pos[0..2];
			if (file_out) {
				rv = iso_ops_ptr.select_file(card, &path, file_out);
				if (file_out && *file_out)
					file_type = (**file_out).type;
			}
			else {
				sc_file* file = sc_file_new();
				file.path = path;
			  rv = iso_ops_ptr.select_file(card, &path, &file /*null ?*/);
				file_type = file.type;
				sc_file_free(file);
			}
			diff = (file_type == SC_FILE_TYPE_DF ? 0 : 2);
		}
		in_len -= 2;
		in_pos += 2;
	} while (in_len && rv == SC_SUCCESS);

	/* adapt card->cache.current_df->path */
	if (rv==SC_SUCCESS) with (card.cache) {
		memset(&current_df.path, 0, sc_path.sizeof);
		if (in_path_complete) {
			current_df.path.len = (in_path.len      == 2 ? 2 : in_path.len-diff);
			memcpy(current_df.path.value.ptr, in_path.value.ptr, current_df.path.len);
			valid = 1;
		}
		else if (p_path != in_path) { /* we have path_substitute */
			current_df.path.len = (path_substitute.len == 2 ? 2 : path_substitute.len-diff);
			memcpy(current_df.path.value.ptr, path_substitute.value.ptr, current_df.path.len);
			valid = 1;
		}
		else
			valid = 0;
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file_by_path",
			"ending with card->cache.current_df->path=%s, card->cache.valid=%d",	sc_print_path(&current_df.path), valid);
	}
	else with (card.cache) {
		current_df.path = MF_path;
		valid = 1;
	}

	return rv;
}


private extern(C) int acos5_64_select_file(sc_card* card, const(sc_path)* path, sc_file** file_out)
{
/* acos can handle path->type SC_PATH_TYPE_FILE_ID (P1=0) and SC_PATH_TYPE_DF_NAME (P1=4) only.
Other values for P1 are not supported.
We have to take care for SC_PATH_TYPE_PATH and (maybe those are used too)
SC_PATH_TYPE_FROM_CURRENT as well as SC_PATH_TYPE_PARENT */
/* FIXME if path is SC_PATH_TYPE_DF_NAME, card->cache.current_df->path is not adapted */
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_INS_NOT_SUPPORTED;
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file",
		"called with path->type: %d\n", path.type);
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_select_file",
				"returning with: %d\n", rv);
	}

	final switch (cast(SC_PATH_TYPE)path.type) {
		case SC_PATH_TYPE_FILE_ID:
			goto case SC_PATH_TYPE_PATH;
		case SC_PATH_TYPE_DF_NAME:
			rv = iso_ops_ptr.select_file(card, path, file_out);
			if (file_out && *file_out && (**file_out).path.len > 0) {
				/* TODO test this */
				card.cache.current_df.path = (**file_out).path;
				card.cache.valid = 1; /* maybe not starting with 3F00 */
			}
			else
				card.cache.valid = 0;
			return rv;
		case SC_PATH_TYPE_PATH:
			return rv=acos5_64_select_file_by_path(card, path, file_out);
		case SC_PATH_TYPE_PATH_PROT:
			return rv;
		case SC_PATH_TYPE_FROM_CURRENT, SC_PATH_TYPE_PARENT:
			goto case SC_PATH_TYPE_PATH;
	}
}


/**
 *  The iso7816.c -version get_challenge get's wrapped to have RNDc known by terminal/host in sync with card's last SM_SMALL_CHALLENGE_LEN challenge handed out
 *  len is restricted to be a multiple of 8 AND 8<=len
 */
private extern(C) int acos5_64_get_challenge(sc_card* card, ubyte* rnd, size_t len)
{
	int rv = SC_ERROR_UNKNOWN;
	sc_context* ctx = card.ctx;
	mixin (log!(q{"acos5_64_get_challenge"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_challenge",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_challenge",
				"returning with: %d\n", rv);
	}

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_challenge",
		"len: %lu\n", len);
	if (len==0)
		return rv=SC_SUCCESS;
	if (len<SM_SMALL_CHALLENGE_LEN /*|| (len%SM_SMALL_CHALLENGE_LEN)*/) {
		rv = -1;
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_challenge",
			"called with inappropriate len arument: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}

	ubyte* p_rnd = rnd;
	size_t p_len = len;
version(ENABLE_SM)
	with (card.sm_ctx.info.session.cwa)
	if (p_rnd == null) {
		p_rnd = icc.rnd.ptr;
		p_len = icc.rnd.length;
	}

	if ((rv=iso_ops_ptr.get_challenge(card, p_rnd, p_len)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_challenge",
			"iso_ops_ptr.get_challenge failed: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}

version(ENABLE_SM)
	with (card.sm_ctx.info.session.cwa) {
		if (p_rnd != icc.rnd.ptr)
			icc.rnd        = p_rnd[(p_len-SM_SMALL_CHALLENGE_LEN) .. p_len]; // SM_SMALL_CHALLENGE_LEN==8;
////		card_challenge = icc.rnd;
		ssc              = icc.rnd;
	} // version(ENABLE_SM)

	return rv;
}

private extern(C) int acos5_64_logout(sc_card *card)
{
/* ref. manual:  7.2.2. Logout
Logout command is used to de-authenticate the user's global or local PIN access condition status.
The user controls PIN rights without resetting the card and interrupting the flow of events.
[The same may be achieved simply be selecting a different DF(/MF)]
7.2.7.
 De-authenticate
This command allows ACOS5-64 to de-authenticate the authenticated key without resetting the card.

TODO Check if 'Logout' does all we want or if/when we need 'De-authenticate' too
 */
	sc_context* ctx = card.ctx;
	mixin (log!(q{"acos5_64_logout"}, q{"called"})); //
	int rv;
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_logout",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_logout",
			"returning with: %d\n", rv);
	}

	sc_apdu apdu; //                           CLAINSP1 P2
	bytes2apdu(ctx, cast(immutable(ubyte)[4])x"80 2E 00 81", apdu);

	if ((rv = sc_transmit_apdu(card, &apdu)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_logout",
			"APDU transmit failed: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}

	return rv = sc_check_sw(card, apdu.sw1, apdu.sw2);
}

enum {
	from_env,
	from_usage,
}

/** constructs the the "ubyte-string" for set security environment beginning with CRT template tag
 *  2 modes: 'from_env' taking input from sc_security_env or 'from_usage' taking input from the other parameters */
uba construct_sc_security_env (int mode, const(sc_security_env)* psec_env, Template_Tag tt, Usage usage=None,
	ubyte id_pin_key_local_global_or_key_session=0xFF/*None*/, ubyte algo=0xFF/*None, or infer*/, uba keyFile_RSA=null, uba iv=null)
{
	uba result;

	if (mode==from_env) {
		if (!psec_env)
			return result;
		with (*psec_env)   {
			if (!(flags & SC_SEC_ENV_ALG_PRESENT) || algorithm != SC_ALGORITHM_RSA /*|| algorithm_flags != SC_ALGORITHM_RSA_RAW*/)
				return result;
			if (!(flags & (SC_SEC_ENV_FILE_REF_PRESENT | SC_SEC_ENV_KEY_REF_PRESENT)))
				return result;
			final switch (cast(SC_SEC_OPERATION)operation) {
				case SC_SEC_OPERATION_DECIPHER:
					tt    = Template_Tag.CT_asym;
					usage = Usage.Decrypt_PSO_priv; // Decrypt_PSO_priv, Decrypt_PSO_SMcommand_priv, Decrypt_PSO_SMresponse_priv, Decrypt_PSO_SMcommandResponse_priv,
					break;
				case SC_SEC_OPERATION_SIGN:
					tt    = Template_Tag.DST;
					usage = Usage.Sign_PKCS1_priv;
					break;
				case SC_SEC_OPERATION_AUTHENTICATE:  break;
				case SC_SEC_OPERATION_DERIVE:        break;
			}
			if (flags & SC_SEC_ENV_FILE_REF_PRESENT) {
				if (file_ref.len<2)
					return result;
				with (file_ref) keyFile_RSA = value[len-2..len].dup;
			}
			else {
				sc_path path;
				sc_format_path("41F0", &path);
				path.value[1] |= key_ref[0];
				with (path) keyFile_RSA = value[len-2..len].dup;
			}
		} // with (*psec_env) {
	} // if (mode==from_env)

	if (keyFile_RSA !is null && keyFile_RSA.length!=2)
		return result;

	result = [tt==CT_asym? cast(ubyte)(tt-1) : cast(ubyte)tt] ~ ubZero; // length not known yet: 0 to be replaced later
	ubyte res_uqb, res_algo, res_idpk;
	ubyte uqb;

	switch (tt) {
		case HT :     assert(aa_uqb_poss[tt].list.length==0); uqb = 0xFF;                          break;
		case AT :     assert(aa_uqb_poss[tt].list.length >0); uqb = aa_uqb_poss[tt].list[usage-1]; break;
		case DST:     assert(aa_uqb_poss[tt].list.length >0); uqb = aa_uqb_poss[tt].list[usage-4]; algo=(usage -4<2? 0x10 : 0x11); break;
		case CT_asym: assert(aa_uqb_poss[tt].list.length >0); uqb = aa_uqb_poss[tt].list[usage-8]; algo=(usage -8<4? 0x13 : 0x12); break;
		case CT_sym:  assert(aa_uqb_poss[tt].list.length >0); break;
		case CCT:     assert(aa_uqb_poss[tt].list.length>=2);                                      algo=0x02; // SM: always algo 02
									uqb =  aa_uqb_poss[tt].list[(usage-16)%2]; break;//(usage-16<2? aa_uqb_poss[tt].list[0] : aa_uqb_poss[tt].list[1]); break;
		default:
			break;
	}

	// .mandatory_And
	// has tt an UQB requirement? if required, SubDO_Tag.UQB always is in .mandatory_And
	if (canFind(aa_crt_tags[tt].mandatory_And, SubDO_Tag.UQB)) {
		result ~= [cast(ubyte)SubDO_Tag.UQB, ubyte(1)];
		if (aa_uqb_poss[tt].list.length) { // otherwise aa_uqb_poss[tt].list is ill-defined and the APDU command will fail
			res_uqb = canFind(aa_uqb_poss[tt].list, uqb)? uqb : aa_uqb_poss[tt].list[0];
			result ~= res_uqb;
		}
	}
	// has tt an algo requirement? if required, SubDO_Tag.Algorithm always is in .mandatory_And
	if (canFind(aa_crt_tags[tt].mandatory_And, SubDO_Tag.Algorithm)) {
		result ~= [cast(ubyte)SubDO_Tag.Algorithm, ubyte(1)];
		if (aa_alg_poss[tt].list.length) { // otherwise aa_alg_poss[tt].list is ill-defined and the APDU command will fail
			res_algo = canFind(aa_alg_poss[tt].list, algo)? algo : aa_alg_poss[tt].list[0];
			result ~= res_algo;
		}
	}
	// has tt an KeyFile_RSA requirement? if required, SubDO_Tag.KeyFile_RSA always is in .mandatory_And
	if (canFind(aa_crt_tags[tt].mandatory_And, SubDO_Tag.KeyFile_RSA)) {
		if (keyFile_RSA.length<2)
			keyFile_RSA = [ubyte(0),ubyte(0)];
		result ~= [cast(ubyte)SubDO_Tag.KeyFile_RSA, ubyte(2)] ~ keyFile_RSA;
//		if (aa_keyFile_RSA_poss[tt].list !is null) {
//		}
	}

	// has tt an ID_Pin_Key_Local_Global requirement in .mandatory_And? must be AT
	if (canFind(aa_crt_tags[tt].mandatory_And, SubDO_Tag.ID_Pin_Key_Local_Global)) {
		result ~= [cast(ubyte)SubDO_Tag.ID_Pin_Key_Local_Global, ubyte(1)];
		if (aa_idpk_poss[tt].list.length) { // otherwise aa_idpk_poss[tt].list is ill-defined and the APDU command will fail
			res_idpk = canFind(aa_idpk_poss[tt].list, id_pin_key_local_global_or_key_session)? id_pin_key_local_global_or_key_session : aa_idpk_poss[tt].list[0];
			result ~= res_idpk;
		}
	}
	// has tt 
	if (canFind(aa_crt_tags[tt].mandatory_OneOf, SubDO_Tag.HP_Key_Session)) {
		if (tt==CCT && (usage-16)/2 == 0)
			result ~= [cast(ubyte)SubDO_Tag.HP_Key_Session, ubyte(0)];
		else {
			result ~= [cast(ubyte)SubDO_Tag.ID_Pin_Key_Local_Global, ubyte(1)];
			if (aa_idpk_poss[tt].list.length) { // otherwise aa_idpk_poss[tt].list is ill-defined and the APDU command will fail
				res_idpk = canFind(aa_idpk_poss[tt].list, id_pin_key_local_global_or_key_session)? id_pin_key_local_global_or_key_session : aa_idpk_poss[tt].list[(usage-16)/2];
				result ~= res_idpk;
			}
		}
	}
	// has tt an optional Initial_Vector in .optional_SymKey? must be CT_sym or CCT
	if (canFind(aa_crt_tags[tt].optional_SymKey, SubDO_Tag.Initial_Vector) && iv !is null && iv.length==8)
		result ~= [cast(ubyte)SubDO_Tag.Initial_Vector, ubyte(8)] ~ iv;

	if (result.length>1)
		result[1] = cast(ubyte)(result.length-2);
//	}
	return result;
}

unittest {
	assert(equal(construct_sc_security_env(1, null,     HT                  ), [0xAA, 0x03, 0x80, 0x01, 0x21][]));
	assert(equal(construct_sc_security_env(1, null,     HT, None, 0xFF, 0xFF), [0xAA, 0x03, 0x80, 0x01, 0x21][]));
	assert(equal(construct_sc_security_env(1, null,     HT, None, 0xFF, 0x20), [0xAA, 0x03, 0x80, 0x01, 0x20][]));
	assert(equal(construct_sc_security_env(1, null,     AT, Pin_Verify_and_SymKey_Authenticate), [0xA4, 0x06, 0x95, 0x01, 0x88, 0x83, 0x01, 0x81][]));
	assert(equal(construct_sc_security_env(1, null,     AT, SymKey_Authenticate),                [0xA4, 0x06, 0x95, 0x01, 0x80, 0x83, 0x01, 0x81][]));
	assert(equal(construct_sc_security_env(1, null,     AT, Pin_Verify),                         [0xA4, 0x06, 0x95, 0x01, 0x08, 0x83, 0x01, 0x81][]));
	assert(equal(construct_sc_security_env(1, null,     AT, Pin_Verify, 0x82),                   [0xA4, 0x06, 0x95, 0x01, 0x08, 0x83, 0x01, 0x82][]));
	assert(equal(construct_sc_security_env(1, null,     AT, SymKey_Authenticate, 0x82),          [0xA4, 0x06, 0x95, 0x01, 0x80, 0x83, 0x01, 0x82][]));
	assert(equal(construct_sc_security_env(1, null,DST,Sign_PKCS1_priv, 0xFF,0xFF,[ubyte(0x41), ubyte(0xF1)]), [0xB6, 0x0A, 0x95, 0x01, 0x40, 0x80, 0x01, 0x10, 0x81, 0x02, 0x41, 0xF1][]));
	assert(equal(construct_sc_security_env(1, null,DST,Verify_PKCS1_pub,0xFF,0xFF,[ubyte(0x41), ubyte(0x31)]), [0xB6, 0x0A, 0x95, 0x01, 0x80, 0x80, 0x01, 0x10, 0x81, 0x02, 0x41, 0x31][]));
	assert(equal(construct_sc_security_env(1, null,DST,Sign_9796_priv,  0xFF,0xFF,[ubyte(0x41), ubyte(0xF2)]), [0xB6, 0x0A, 0x95, 0x01, 0x40, 0x80, 0x01, 0x11, 0x81, 0x02, 0x41, 0xF2][]));
	assert(equal(construct_sc_security_env(1, null,DST,Verify_9796_pub, 0xFF,0xFF,[ubyte(0x41), ubyte(0x32)]), [0xB6, 0x0A, 0x95, 0x01, 0x80, 0x80, 0x01, 0x11, 0x81, 0x02, 0x41, 0x32][]));
	assert(equal(construct_sc_security_env(1, null,CT_asym,Usage.Decrypt_PSO_priv, 0xFF,0xFF,[ubyte(0x41), ubyte(0xF1)]),             [0xB8, 0x0A, 0x95, 0x01, 0x40, 0x80, 0x01, 0x13, 0x81, 0x02, 0x41, 0xF1][]));
	assert(equal(construct_sc_security_env(1, null,CT_asym,Decrypt_PSO_SMcommandResponse_priv, 0xFF,0xFF,[ubyte(0x41), ubyte(0xF1)]), [0xB8, 0x0A, 0x95, 0x01, 0x70, 0x80, 0x01, 0x13, 0x81, 0x02, 0x41, 0xF1][]));
	assert(equal(construct_sc_security_env(1, null,CT_asym,Encrypt_PSO_pub, 0xFF,0xFF,[ubyte(0x41), ubyte(0x31)]),                    [0xB8, 0x0A, 0x95, 0x01, 0x40, 0x80, 0x01, 0x12, 0x81, 0x02, 0x41, 0x31][]));
	assert(equal(construct_sc_security_env(1, null,CT_asym,Encrypt_PSO_SMcommandResponse_pub, 0xFF,0xFF,[ubyte(0x41), ubyte(0x31)]),  [0xB8, 0x0A, 0x95, 0x01, 0x70, 0x80, 0x01, 0x12, 0x81, 0x02, 0x41, 0x31][]));

	assert(equal(construct_sc_security_env(1, null,CCT,Session_Key_SM), [0xB4, 0x08, 0x95, 0x01, 0x30, 0x80, 0x01, 0x02, 0x84, 0x00][]));
	assert(equal(construct_sc_security_env(1, null,CCT,Local_Key1, 0xFF, 0xFF, null, [8,7,6,5,4,3,2,1]), [0xB4, 0x13, 0x95, 0x01, 0x40, 0x80, 0x01, 0x02, 0x83, 0x01, 0x81, 0x87, 0x08, 0x08,0x07,0x06,0x05,0x04,0x03,0x02,0x01][]));

	sc_security_env sec_enc;
	with (sec_enc) {
		flags     = SC_SEC_ENV_ALG_PRESENT | SC_SEC_ENV_KEY_REF_PRESENT | SC_SEC_ENV_FILE_REF_PRESENT;
		operation = SC_SEC_OPERATION_DECIPHER;
		algorithm = SC_ALGORITHM_RSA;
		algorithm_flags = SC_ALGORITHM_RSA_RAW;
		algorithm_ref   = 0;
		sc_format_path("41F3", &file_ref);
		key_ref[0]      = 3;
		key_ref_len     = 1;
	}
	assert(equal(construct_sc_security_env(0, &sec_enc, Template_Tag.HT, Usage.None), [0xB8, 0x0A, 0x95, 0x01, 0x40, 0x80, 0x01, 0x13, 0x81, 0x02, 0x41, 0xF3][]));

	writeln("PASSED: construct_sc_security_env"); // Decrypt_RSA_priv
}


private extern(C) int acos5_64_set_security_env(sc_card* card, const(sc_security_env)* env, int se_num)
{
	assert(card != null && env != null);

	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_set_security_env"}, q{"called"})); //
	scope(exit) {
		(cast(acos5_64_private_data*) card.drv_data).security_env = *env;
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_set_security_env",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_set_security_env",
				"returning with: %d\n", rv);
	}
/* */
	version(ENABLE_TOSTRING) {
		writer.put("int acos5_64_set_security_env(sc_card* card, const(sc_security_env)* env, int se_num) called with argument se_num, *env:\n");
		writer.formattedWrite("%s\n", se_num);
		writer.formattedWrite("%s", *env);
	}

	sc_apdu apdu;
	ubyte[SC_MAX_APDU_BUFFER_SIZE] sbuf;
	ubyte* p;
	int locked = 0;

	sc_format_apdu(card, &apdu, SC_APDU_CASE_3_SHORT, 0x22, 0x01, 0);
	p = sbuf.ptr;
	if (env.algorithm==SC_ALGORITHM_RSA &&
			(env.operation==SC_SEC_OPERATION_DECIPHER || env.operation==SC_SEC_OPERATION_SIGN)) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_set_security_env",
			"about to call construct_sc_security_env with env.operation(%d), env.flags(%u), env.key_ref[0](%02X)\n", env.operation, env.flags, env.key_ref[0]);
		uba res = construct_sc_security_env (from_env, env, Template_Tag.NA);
		if (res.length>1) {
			apdu.p2 = res[0];
			res = res [2..$];
			p[0..res.length] = res[];
			p += res.length;
		}
	}
	else {
	*p++ = 0x95;
	*p++ = 0x01;
	*p++ = (env.operation==6 ? 0x80 : (env.operation==3 ? 0xC0 : 0x40)); /* 0x80: public key usage; 0x40 : priv. key usage */

	if (env.flags & SC_SEC_ENV_FILE_REF_PRESENT) {
		*p++ = 0x81;
		*p++ = cast(ubyte)env.file_ref.len;
		assert(sbuf.length - (p - sbuf.ptr) >= env.file_ref.len);
		memcpy(p, env.file_ref.value.ptr, env.file_ref.len);
		p += env.file_ref.len;
	}

	*p++ = 0x80; /* algorithm reference */
	*p++ = 0x01;
	
//	sc_apdu apdu2;
	switch (env.operation) {
	case SC_SEC_OPERATION_DECIPHER:
		*p++ = 0x13;
		apdu.p2 = 0xB8;
		break;
	case SC_SEC_OPERATION_SIGN:
		*p++ = 0x10;
		apdu.p2 = 0xB6;
		break;
	case SC_SEC_OPERATION_AUTHENTICATE:
		*p++ = cast(ubyte)(env.flags & SC_SEC_ENV_ALG_REF_PRESENT? env.algorithm_ref & 0xFF : 0x00);
		apdu.p2 = 0xB8;
		break;
	case 5: // my encoding for SC_SEC_GENERATE_RSAKEYS_PRIVATE
		goto case SC_SEC_OPERATION_SIGN;
	case 6: // my encoding for SC_SEC_GENERATE_RSAKEYS_PUBLIC
		goto case SC_SEC_OPERATION_SIGN;
	default:
		return SC_ERROR_INVALID_ARGUMENTS;
	}

/+
	if (env.flags & SC_SEC_ENV_ALG_REF_PRESENT) {
		*p++ = 0x80;	 algorithm reference
		*p++ = 0x01;
		*p++ = env.algorithm_ref & 0xFF;
	}
+/
/* page 47 */
	if (env.operation!=SC_SEC_OPERATION_SIGN && (env.flags & SC_SEC_ENV_KEY_REF_PRESENT)) {
//		if (env.flags & SC_SEC_ENV_KEY_REF_ASYMMETRIC)
			*p++ = 0x83;
//		else
//			*p++ = 0x84;
		*p++ = cast(ubyte)env.key_ref_len;
		assert(sbuf.sizeof - (p - sbuf.ptr) >= env.key_ref_len);
		memcpy(p, env.key_ref.ptr, env.key_ref_len);
		p += env.key_ref_len;
	}
/* */
	} //else
	rv = cast(int)(p - sbuf.ptr);
	apdu.lc = rv;
	apdu.datalen = rv;
	apdu.data = sbuf.ptr;
	if (se_num > 0) {

		if ((rv=sc_lock(card)) < 0) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_set_security_env",
				"sc_lock() failed");
			return rv;
		}
		locked = 1;
	}
	if (apdu.datalen != 0) {
		rv = sc_transmit_apdu(card, &apdu);
		if (rv) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_set_security_env",
				"%s: APDU transmit failed", sc_strerror(rv));
			goto err;
		}
		rv = sc_check_sw(card, apdu.sw1, apdu.sw2);
		if (rv) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_set_security_env",
				"%s: Card returned error", sc_strerror(rv));
			goto err;
		}
		if (env.operation==SC_SEC_OPERATION_SIGN) {
			ubyte[SC_MAX_APDU_BUFFER_SIZE] sbuf2;
			sc_apdu apdu2;
			with (env.file_ref)
			bytes2apdu(card.ctx, cast(immutable(ubyte)[3])x"00 22 01"~construct_sc_security_env(1, null, CT_asym, Usage.Decrypt_PSO_priv, 0xFF, 0xFF, value[len-2..len].dup), apdu2);

			rv = sc_transmit_apdu(card, &apdu2);
			if (rv) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_set_security_env",
					"%s: APDU transmit failed", sc_strerror(rv));
				goto err;
			}
			rv = sc_check_sw(card, apdu2.sw1, apdu2.sw2);
			if (rv) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_set_security_env",
					"%s: Card returned error", sc_strerror(rv));
				goto err;
				}
		}
	}
	if (se_num <= 0)
		return rv=SC_SUCCESS;
	sc_format_apdu(card, &apdu, SC_APDU_CASE_3_SHORT, 0x22, 0xF2, se_num); // Store Security Environment ?
	rv = sc_transmit_apdu(card, &apdu);

	sc_unlock(card);
	if (rv < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_set_security_env",
			"APDU transmit failed");
		return rv;
	}

	return sc_check_sw(card, apdu.sw1, apdu.sw2);
err:
	if (locked)
		sc_unlock(card);

	return rv;
}

version(OPENSC_VERSION_LATEST)
private extern(C) int acos5_64_decipher(sc_card* card, const(ubyte)* in_, /*in*/ size_t in_len, ubyte* out_, /*in*/ size_t out_len)
{ // check in_len, out_len, they aren't constant any more, but treat them as if they are constant

//Fixme currently it is for RSA only, but must take care of symkey decrypt as well
	assert(card != null && in_ != null && out_ != null);
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_decipher"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
				"returning with: %d\n", rv);
	}
	bool call_to_compute_signature_in_progress = (cast(acos5_64_private_data*) card.drv_data).call_to_compute_signature_in_progress;
/* */
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
		"in_len:  %llu\n", in_len);
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
		"out_len: %llu\n", out_len);

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
		"card.algorithms.algorithm: %u\n", card.algorithms.algorithm); // SC_ALGORITHM_RSA = 0
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
		"card.algorithms.flags: 0x%08X\n", card.algorithms.flags); // 0x80000_23B  

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
		"card.algorithms.u._rsa.exponent: %lu\n", card.algorithms.u._rsa.exponent);
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
		"card.algorithm_count: %d\n", card.algorithm_count);

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
		"card.caps:  %d\n", card.caps);
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
		"card.flags: %d\n", card.flags);

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
		"Input to decipher len: '%d' bytes:\n%s\n============================================================",
		in_len, sc_dump_hex(in_, in_len));
/* */
	if (in_len > out_len)
		return rv=SC_ERROR_NOT_SUPPORTED;
	if (in_len > 0x0200) // FIXME stimmt nur für RSA
		return rv=SC_ERROR_NOT_SUPPORTED;

version(ENABLE_ACOS5_64_UI) {
	/* (Requested by DGP): on signature operation, ask user consent */
	if (call_to_compute_signature_in_progress && (rv=acos5_64_ask_user_consent(card, user_consent_title, user_consent_message)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher", "User consent denied\n");
		return rv;
	}
}

	sc_apdu apdu;
	sc_format_apdu(card, &apdu, SC_APDU_CASE_3_SHORT, 0x2A, 0x80, 0x84);
	apdu.flags = SC_APDU_FLAGS_NO_GET_RESP;
	apdu.data  = in_;
	apdu.lc    = apdu.datalen = in_len;

	if (in_len > 0xFF)
		apdu.flags  |= SC_APDU_FLAGS_CHAINING;

	if ((rv=sc_transmit_apdu(card, &apdu)) < 0) { // able to apply chaining properly with flag SC_APDU_FLAGS_CHAINING
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
			"APDU transmit failed\n");
		return rv;
	}
		
	if (!(apdu.sw1 == 0x61 && apdu.sw2 == (in_len>0xFF? 0x00 : in_len & 0x00FF))) {	
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
			"Didn't get clearance to call get_response: sw1: %X, sw2: %X\n", apdu.sw1, apdu.sw2);
		return rv=SC_ERROR_UNKNOWN;
	}

	size_t received;
	ubyte[0x200] parr;
		size_t count;
		ubyte* p = parr.ptr;
		do { // emulate kind of 'chaining' of get_response; acos doesn't tell properly for keys>2048 bits how much to request, thus we have to fall back to in_len==keyLength
			count = in_len - received; // here count is: 'not_received'
			if ((rv=iso_ops_ptr.get_response(card, &count, p)) < 0) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
					"rv: %d, count:%lu , \n", rv, count);
				return rv;
			}
			received += count; // now count is what actually got received
			p        += count;
		} while (in_len > received && count>0);
	
/* */
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
		"Output from decipher len: '%d' bytes:\n%s\n============================================================",
			received, sc_dump_hex(parr.ptr, received));
	if (in_len != received)
		return rv=SC_ERROR_UNKNOWN;

	size_t out_len_new = received;
version(RSA_PKCS_PSS) {
		if (call_to_compute_signature_in_progress)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__,   "acos5_64_decipher", "MESSAGE FROM PRIVATE KEY USAGE: No checking of padding for PKCS_PPS took place currently (other than last byte = 0xbc)\n"); //
		else {
		  
		}
}
else {
	if      (card.algorithms.flags & SC_ALGORITHM_RSA_PAD_PKCS1) {
		if ((rv=sc_pkcs1_strip_02_padding(ctx, parr.ptr, received, out_, &out_len_new)) < 0) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
				"MESSAGE FROM PRIVATE KEY USAGE: SC_ALGORITHM_RSA_PAD_PKCS1 is defined; padding of cryptogram is wrong (NOT BT=02  or other issue)\n");
			return rv;
		}
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
			"MESSAGE FROM PRIVATE KEY USAGE: SC_ALGORITHM_RSA_PAD_PKCS1 is defined; the cryptogram was padded correctly (BT=02); padding got stripped\n");
	}
	else if (card.algorithms.flags & SC_ALGORITHM_RSA_RAW) {
		if (call_to_compute_signature_in_progress)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__,   "acos5_64_decipher", "MESSAGE FROM PRIVATE KEY USAGE: The digestInfo(prefix+hash) was padded correctly for signing (BT=01)\n"); //
		else {
			rv = sc_pkcs1_strip_02_padding(ctx, parr.ptr, received, null, &out_len_new); // this is a check only, out_len_new doesn't get changed
			if (rv==SC_SUCCESS)
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher", "MESSAGE FROM PRIVATE KEY USAGE: SC_ALGORITHM_RSA_RAW is defined (NOTHING has to be stripped); the cryptogram was padded correctly (BT=02)\n");
			else {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher", "MESSAGE FROM PRIVATE KEY USAGE: SC_ALGORITHM_RSA_RAW is defined (NOTHING has to be stripped); the cryptogram was NOT padded correctly for deciphering (BT=02)\n");
				return rv;
			}
		}
		out_[0..out_len_new] = parr[0..out_len_new];
	}
	else 
		return rv=SC_ERROR_NOT_SUPPORTED;
}
/* */
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_decipher",
		"MESSAGE FROM PRIVATE KEY USAGE: Private key was successfully applied for decryption");
	return rv=cast(int)out_len_new;
}

version(RSA_PKCS_PSS) {
/* requires my yet unpublished:
	"dependencies" : {
		"pkcs11": "~>2.20.3"
	},
	"subConfigurations": {
		"pkcs11": "deimos"
	},
*/
import pkcs11.types;

/+
as long as PSS support for RSA-SSA-PKCS is missing in opensc, required parameters are based on PKCS#11 header's structs, constants (import pkcs11.types)

mechanism: CKM_RSA_PKCS_PSS is generic, there are more specific ones that include digesting with a denoted digest algorithm
CK_RSA_PKCS_PSS_PARAMS pss_params = e.g. CK_RSA_PKCS_PSS_PARAMS(CKM_SHA256, CKG_MGF1_SHA256, 32 sLen==hLen);
+/
private extern(C) int pkcs1_add_PSS_padding(const(ubyte)*in_/* data_hashed */, size_t in_len /* data_hashedLen*/,
	ubyte* out_/*EM*/, size_t* out_len/* in: *out_len>=rsa_size_bytes_modulus; out: rsa_size_bytes_modulus==emLen*/,
	size_t	rsa_size_bytes_modulus, size_t	bn_num_bits_modulus, CK_RSA_PKCS_PSS_PARAMS_PTR pss_params) {
	import std.stdio;
	import std.digest.digest;
	import std.digest.sha;
	import deimos.openssl.rand : RAND_bytes;
//	import std.random; // doesn't work so far:   Random rng = rndGen(); salt = cast(ubyte[]) rng.take(sLen).array; used openssl's random instead

	uba MGF1(in uba mgfSeed, size_t maskLen, CK_RSA_PKCS_MGF_TYPE hashAlg_mgf1) {
		uba T = new ubyte[0];
		size_t  hLen_mgf1;
		uba hash_mgfSeed;

		switch (hashAlg_mgf1) {
			case CKG_MGF1_SHA1:   hLen_mgf1=20; hash_mgfSeed = digest!SHA1  (mgfSeed); break;
			case CKG_MGF1_SHA256: hLen_mgf1=32; hash_mgfSeed = digest!SHA256(mgfSeed); break;
			case CKG_MGF1_SHA384: hLen_mgf1=48; hash_mgfSeed = digest!SHA384(mgfSeed); break;
			case CKG_MGF1_SHA512: hLen_mgf1=64; hash_mgfSeed = digest!SHA512(mgfSeed); break;
			case CKG_MGF1_SHA224: hLen_mgf1=28; hash_mgfSeed = digest!SHA224(mgfSeed); break;
			default:
				return T.dup;
		}

		if (maskLen > 0x1_0000_0000UL*hLen_mgf1)
			return T.dup; // output "mask too long" and stop.

		foreach (i; 0..(maskLen / hLen_mgf1 + (maskLen % hLen_mgf1 != 0)))
			T ~= hash_mgfSeed.dup ~ integral2ub!4(i);

		assert(T.length>=maskLen);
		T.length = maskLen;
		return T.dup;
	} // MGF1

	if (*out_len<rsa_size_bytes_modulus)
		return SC_ERROR_INTERNAL;

	size_t emBits = bn_num_bits_modulus-1; /* (intended) length in bits of an encoded message EM */
	size_t emLen  = emBits/8 + (emBits % 8 != 0);
	ubyte hLen;
	switch (pss_params.hashAlg) {
		case CKM_SHA_1:  hLen=20; break;
		case CKM_SHA256: hLen=32; break;
		case CKM_SHA384: hLen=48; break;
		case CKM_SHA512: hLen=64; break;
		case CKM_SHA224: hLen=28; break;
		default:
			return SC_ERROR_INTERNAL;
	}

	int sLen  = cast(int)pss_params.sLen;

//      3.   If emLen < hLen + sLen + 2, output "encoding error" and stop.
	if (emLen < hLen + sLen + 2)
		return SC_ERROR_INTERNAL; // output "encoding error" and stop.
//      2.   Let mHash = Hash(M), an octet string of length hLen.
//      4.   Generate a random octet string salt of length sLen; if sLen = 0, then salt is the empty string.
	uba salt  = new ubyte[sLen];
	if (sLen>0 && RAND_bytes(salt.ptr, sLen) != 1)
		return SC_ERROR_INTERNAL;

//      5.   Let  M' = (0x)00 00 00 00 00 00 00 00 || mHash || salt;  M' is an octet string of length 8 + hLen + sLen with eight initial zero octets.
	uba M1 = cast(uba)x"00 00 00 00 00 00 00 00" ~ /*mHash*/ in_[0..in_len] ~ salt;
	assert(M1.length == 8+hLen+sLen);

//      6.   Let H = Hash(M'), an octet string of length hLen.
	uba  H; // H.length == hLen == mHash.length;
	switch (pss_params.hashAlg) {
		case CKM_SHA_1:  H = digest!SHA1  (M1); break;
		case CKM_SHA256: H = digest!SHA256(M1); break;
		case CKM_SHA384: H = digest!SHA384(M1); break;
		case CKM_SHA512: H = digest!SHA512(M1); break;
		case CKM_SHA224: H = digest!SHA224(M1); break;
		default:
			return SC_ERROR_INTERNAL;
	}
	assert(H.length==hLen);

//      7.   Generate an octet string PS consisting of emLen - sLen - hLen - 2
//           zero octets.  The length of PS may be 0.
	uba PS = new ubyte[emLen - sLen - hLen - 2];
	assert(PS.length==emLen - sLen - hLen - 2);
	assert(!any(PS));

//      8.   Let DB = PS || 0x01 || salt;  DB is an octet string of length emLen - hLen - 1.
	uba DB = PS ~ ubyte(0x01) ~ salt;
	assert(DB.length==emLen - hLen - 1);
	
//      9.   Let dbMask = MGF(H, emLen - hLen - 1).
	uba dbMask = MGF1(H, emLen - hLen - 1, pss_params.mgf);
	assert(dbMask.length==DB.length);

//      10.  Let maskedDB = DB \xor dbMask.
	uba maskedDB = new ubyte[DB.length];
	maskedDB[] = DB[] ^ dbMask[];
	assert(maskedDB.length==DB.length);

//      11.  Set the leftmost 8emLen - emBits bits of the leftmost octet in maskedDB to zero.
	int rem = emBits % 8;
	if (rem)
		maskedDB[0] &=  2^^rem -1;

//      12.  Let EM = maskedDB || H || 0xbc.
	uba EM = maskedDB ~ H ~ 0xbc;
	assert(EM.length==emLen);

//      13.  Output EM.
	size_t  emLenOffset = rsa_size_bytes_modulus - emLen;
	assert(emLenOffset+EM.length == rsa_size_bytes_modulus);
	if (emLenOffset)
		out_[0..emLenOffset] = 0;
	out_[emLenOffset..emLenOffset+EM.length] = EM[0..EM.length];
	*out_len = rsa_size_bytes_modulus;
	return SC_SUCCESS;
}

unittest {
	import std.stdio;
	import deimos.openssl.rsa : RSA;
	immutable(ubyte)[16] Message = cast(immutable(ubyte)[16])x"0f0e0d0c0b0a09080706050403020100";
	uba     EM = new ubyte[128];
	size_t  EMLen = EM.length;
	CK_RSA_PKCS_PSS_PARAMS pss_params = CK_RSA_PKCS_PSS_PARAMS(CKM_SHA256, CKG_MGF1_SHA256, 32);

	assert(pkcs1_add_PSS_padding(Message.ptr, Message.length, EM.ptr, &EMLen, EMLen, 8*EMLen-(1), &pss_params) == 0);
	assert(EMLen == EM.length);
//	writefln("EM: 0x [%(%02x %)]", EM);
	writeln("PASSED: pkcs1_add_PSS_padding");
}

} // version(RSA_PKCS_PSS)


version(OPENSC_VERSION_LATEST)
/** This function doesn't slavishly perform Computing RSA Signature: Some conditions must be fulfilled, except,
 * it gets either 20 or 32 (, or 0) bytes which are assumed to be a hash from sha1 or sha256 (or a pkcs11-tool test case), but this may result in a verification error due to false assumption.

 * The ACOS function for computing a signature is somewhat special/recuded in capabilitiy:
 * It doesn't accept data well-prepared for signing (padding, digestinfo including hash),
 * but accepts only a hash value (20 bytes=SHA-1 or 32 bytes=SHA-256 or 0 bytes for a hash value
 * already present by an immediate preceding hash calculation by the token; nothing else).
 * The digestInfo and padding (BT=01) is generated by acos before signing automatically, depending on hashLength (20/32 bytes). 
 * In order to mitigate the shortcoming, this function will try (if it can detect {also: does accept} the hash algorithm used)
 * to delegate to raw hash computation,
 * which is possible only, if the RSA key is capabale for decrypting, additional to signing as well!
 * Though this dual key capability is not recommended.
 */
private extern(C) int acos5_64_compute_signature(sc_card* card, const(ubyte)* in_, /*in*/ size_t in_len, ubyte* out_, /*in*/ size_t out_len)
{ // check in_len, out_len, they aren't constant any more, but treat them as if they are constant
	// we got a SHA-512 hash value and this function can not deal with that. Hopefully, the prkey is allowed to decrypt as well, as we will delegate to acos5_64_decipher (raw RSA)
	// There is a signing test, which pads properly, but has no digestinfo(no hash). If the key is capable to decipher as well, we can delegate to acos5_64_decipher. Let's try it.
/*

C_SeedRandom() and C_GenerateRandom():
  seeding (C_SeedRandom) not supported
  seems to be OK
Digests:
  all 4 digest functions seem to work
  MD5: OK
  SHA-1: OK
  RIPEMD160: OK
Signatures (currently only RSA signatures)
  testing key 0 (CAroot) 
ERR: signatures returned by C_SignFinal() different from C_Sign()
  testing signature mechanisms:
    RSA-X-509: OK
    RSA-PKCS: OK
  testing key 1 (4096 bits, label=CAinter) with 1 signature mechanism
    RSA-X-509: OK
  testing key 2 (4096 bits, label=Decrypt) with 1 signature mechanism -- can't be used to sign/verify, skipping
  testing key 3 (4096 bits, label=DecryptSign) with 1 signature mechanism
    RSA-X-509: OK
  testing key 4 (1792 bits, label=DecryptSign2) with 1 signature mechanism
    RSA-X-509: OK
Verify (currently only for RSA):
  testing key 0 (CAroot)
    RSA-X-509:   ERR: verification failed  ERR: C_Verify() returned CKR_SIGNATURE_INVALID (0xc0)

  testing key 1 (CAinter) with 1 mechanism
    RSA-X-509:   ERR: verification failed  ERR: C_Verify() returned CKR_SIGNATURE_INVALID (0xc0)

  testing key 2 (Decrypt) with 1 mechanism
 -- can't be used to sign/verify, skipping
  testing key 3 (DecryptSign) with 1 mechanism
    RSA-X-509: OK
  testing key 4 (DecryptSign2) with 1 mechanism
    RSA-X-509: OK                                                                                                                                                                              
Unwrap: not implemented                                                                                                                                                                        

Decryption (RSA)                                                                                                                                                                               
  testing key 0 (CAroot)  -- can't be used to decrypt, skipping                                                                                                                                
  testing key 1 (CAinter)  -- can't be used to decrypt, skipping                                                                                                                               
  testing key 2 (Decrypt)                                                                                                                                                                      
    RSA-X-509: OK                                                                                                                                                                              
    RSA-PKCS: OK                                                                                                                                                                               
  testing key 3 (DecryptSign)                                                                                                                                                                  
    RSA-X-509: OK                                                                                                                                                                              
    RSA-PKCS: OK                                                                                                                                                                               
  testing key 4 (DecryptSign2)                                                                                                                                                                 
    RSA-X-509: OK                                                                                                                                                                              
    RSA-PKCS: OK                                                                                                                                                                               
5 errors                                                                                                                                                                                       
*/
	if (card == null || in_ == null || out_ == null)
		return SC_ERROR_INVALID_ARGUMENTS;
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;

	acos5_64_private_data* private_data = cast(acos5_64_private_data*) card.drv_data;
	mixin (log!(q{"acos5_64_compute_signature"}, q{"called"}));
	mixin log_scope_exit!("acos5_64_compute_signature");
	scope(exit) {
		private_data.call_to_compute_signature_in_progress = false;
		log_scope_exit_do();
	}
	private_data.call_to_compute_signature_in_progress = true;

/+ +/
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"in_len:  %llu\n", in_len);
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"out_len: %llu\n", out_len);

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"card.algorithms.algorithm: %u\n", card.algorithms.algorithm); // SC_ALGORITHM_RSA = 0
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"card.algorithms.key_length: %u\n", card.algorithms.key_length); // 512
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"card.algorithms.flags: 0x%08X\n", card.algorithms.flags); // 0x80000_23B  

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"card.algorithms.u._rsa.exponent: %lu\n", card.algorithms.u._rsa.exponent);
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"card.algorithm_count: %d\n", card.algorithm_count);

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"card.caps:  %d\n", card.caps);
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"card.flags: %d\n", card.flags);
/+ +/
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"Input to compute_signature len: '%d' bytes:\n%s\n============================================================",
		in_len, sc_dump_hex(in_, in_len));


	if (in_len > out_len)
		return rv=SC_ERROR_NOT_SUPPORTED;
	if (in_len > 0x0200) // FIXME if this function has to decrypt for symkeys as well; currently it's for RSA only
		return rv=SC_ERROR_NOT_SUPPORTED;

	uba tmp_arr = new ubyte[in_len]; // ubyte[0x200] tmp_arr; //	size_t       in_len_new = in_len;
	bool hash_algo_detected;

	if (in_len>=64 /*the min. Modulus*/ && !(cast(int)(in_len%32/*modulusStepSize*/))) { // this must be true (but may depend on SC_ALGORITHM_RSA_PAD_*; check this),  assuming in_len==keyLength
		// padding must exist, be the correct one, possible to be removed, otherwise it's an error
		// the remainder after applying sc_pkcs1_strip_01_padding must be a recognized digestInfo, and this must be allowed to eventually succeed
		{
			size_t  digestInfoLen = in_len; // unfortunately, tmp_arr.length is no lvalue, can't be set by sc_pkcs1_strip_01_padding directly, therfore the scope to get rid of digestInfoLen soon
			// TODO the following is for EMSA-PKCS1-v1_5-ENCODE only, but ther is also EMSA-PSS
			if ((rv=sc_pkcs1_strip_01_padding(ctx, in_, in_len, tmp_arr.ptr, &digestInfoLen)) < 0) { // what remains, should (for RSASSA-PKCS1-v1_5) be a valid ASN.1 DigestInfo with either SHA-1 or SHA-256 digestAlgorithm, otherwise we have to handle that with another function
				//stripp padding BT=01 failed: refuse to sign !
				bool maybe_PSS = in_[in_len-1]==0xbc;
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
					"MESSAGE FROM PRIVATE KEY USAGE: Refused to sign because padding is not correct according EMSA-PKCS1-v1_5 (NOT BT=01 or other issue); maybe_PSS: %d", maybe_PSS);
version(FAKE_SUCCESS_FOR_SIGN_VERIFY_TESTS) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
					"MESSAGE FROM PRIVATE KEY USAGE: Nevertheless, in order to proceed in pkcs11-tool's tests, we fake a success here, knowing, that a verifification of signature will fail !");
				return rv=SC_SUCCESS; // the appropriate SC_ERROR_NOT_SUPPORTED here would stop test procedure in pkcs11-tool, thus we fake a success here and will get a failing verify
}
else version(RSA_PKCS_PSS) {
				if (!maybe_PSS) // TODO possibly more checks before doing Raw RSA
					return rv=SC_ERROR_NOT_SUPPORTED;
				else {
					sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
						"MESSAGE FROM PRIVATE KEY USAGE: RSA_PKCS_PSS is active and we'll try to sign");
					if ((rv=acos5_64_decipher(card, in_, in_len, out_, out_len)) < 0) {
						sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
							"The reason for the error probably is: The key is not capable to decrypt, just sign (every acos RSA-key may sign, but only keys with a flag set for decrypt are allowed to decrypt by acos (established when creating a key pair in token) !");
					}
					return rv;
				}
}
else		return rv=SC_ERROR_NOT_SUPPORTED;
			}
			tmp_arr.length = digestInfoLen;
		} // tmp_arr content is now in_ content without padding; now do the detection
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
			"The in_len got reduced by sc_pkcs1_strip_01_padding from %lu to %lu", in_len, tmp_arr.length);

// what to do with tmp_arr if e.g. only zeros or length to short for hash or digestInfo
		if (!any(tmp_arr)) { // hash algo not retrievable; sc_pkcs1_strip_01_padding succeeded, but the remaining bytes are zeros only; shall we sign? It's worth nothing
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
				"Got a digestInfo (includeing hash) consisting of %lu zeros only!!", tmp_arr.length);
			if (tmp_arr.length<20)
				return rv=SC_ERROR_NOT_ALLOWED;
			
version(TRY_SUCCESS_FOR_SIGN_VERIFY_TESTS) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
				"MESSAGE FROM PRIVATE KEY USAGE: TRY_SUCCESS_FOR_SIGN_VERIFY_TESTS is active and some IMHO unsave steps are taken to try to sign");
			if ((rv=acos5_64_decipher(card, in_, in_len, out_, out_len)) < 0) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
					"The reason for the error probably is: The key is not capable to decrypt, just sign (every acos RSA-key may sign, but only keys with a flag set for decrypt are allowed to decrypt by acos (established when creating a key pair in token) !");
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
					"As a last resort, it's assumed, that a SHA1 hash 20 zero bytes was given");
				tmp_arr.length = 20;
				goto matched_SHA1_or_SHA256;
			}
			return rv;
}
else
			return rv=SC_ERROR_NOT_ALLOWED;
		}

		foreach (ref elem; DI_table[DigestInfo_Algo_RSASSA_PKCS1_v1_5.min .. DigestInfo_Algo_RSASSA_PKCS1_v1_5.max]) /*id_rsassa_pkcs1_v1_5_with_sha1..1+id_rsassa_pkcs1_v1_5_with_sha3_512*/ // foreach (elem; EnumMembers!DigestInfo_Algo_RSASSA_PKCS1_v1_5)
		with (elem) { // a match will leave this function, except for SHA1 and SHA256
			assert(digestInfoPrefix[$-1]              == hashLength);
			assert(digestInfoPrefix.length+hashLength == digestInfoLength);

			if (tmp_arr.length==digestInfoLength && equal(tmp_arr[0..digestInfoPrefix.length], digestInfoPrefix)) { //was memcmp...
				hash_algo_detected = true;

				if (!any(tmp_arr[digestInfoPrefix.length..$])) { // hash algo known, but we got a hash with zeros only; shall we sign a zeroed hash? It's worth nothing
					sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
						"Got a hash with zeros only! Will refuse to sign!");
					return rv=SC_ERROR_NOT_ALLOWED;
				}

				if (!allow) {
					sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
						"I condider hash algorithm %s to be weak and don't allow it !", hashAlgorithmOID.toStringz);
					return rv=SC_ERROR_NOT_ALLOWED;
				}
				if (!compute_signature_possible_without_rawRSA) {
					if ((rv=acos5_64_decipher(card, in_, in_len, out_, out_len)) < 0)
						sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
							"The reason for the error probably is: The key is not capable to decrypt, just sign (every acos RSA-key may sign, but only keys with a flag set for decrypt are allowed to decrypt by acos (established when creating a key pair in token) !");
					return rv;
				}
				// only SHA1 and SHA256, after sc_pkcs1_strip_01_padding and successful detection get to this point
				tmp_arr = tmp_arr[digestInfoPrefix.length..$]; // keep the hash only
				break;
			}
		} // foreach with
		// not yet detected: could still be a hash value without digestInfo
		if (!hash_algo_detected) {
			if (tmp_arr.length!=20 && tmp_arr.length!=32) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
					"Unknown hash algorithm used: Check whether to add to DI_table digestInfoPrefix: %s", sc_dump_hex(tmp_arr.ptr, max(0,tmp_arr.length-tmp_arr[$-1])));
				return rv=SC_ERROR_NOT_IMPLEMENTED;
			}
		}
		//matched SHA1 or SHA256
	} // if (in_len>=64 && !(cast(int)in_len%32))
	else { // (or 20/32 bytes pure hash)
version(RSA_PKCS_PSS) {
		if (in_len==20/* || in_len==32*/) {
/* */
			tmp_arr.length = 512;
			size_t out_len_tmp = 512;
			CK_RSA_PKCS_PSS_PARAMS pss_params = CK_RSA_PKCS_PSS_PARAMS(CKM_SHA_1, CKG_MGF1_SHA1, in_len);
			rv = pkcs1_add_PSS_padding(in_, in_len, tmp_arr.ptr, &out_len_tmp, tmp_arr.length, tmp_arr.length*8, &pss_params);
			assert(rv==0);
			assert(out_len_tmp==512);
			if ((rv=acos5_64_decipher(card, tmp_arr.ptr, tmp_arr.length, out_, out_len)) < 0)
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
					"The reason for the error probably is: The key is not capable to decrypt, just sign (every acos RSA-key may sign, but only keys with a flag set for decrypt are allowed to decrypt by acos (established when creating a key pair in token) !");
			return rv;
/* */
		}
		else
			tmp_arr.length = 0;
}
else {
		if (in_len==20 || in_len==32) {
			tmp_arr.length = in_len;
			tmp_arr[] = in_[0..tmp_arr.length]; 
		}
		else
			tmp_arr.length = 0;
}
	}

matched_SHA1_or_SHA256: // or everything unknown is mapped to zero length, which entails, that acos will try to use an existing internal hash

version(ENABLE_ACOS5_64_UI)  /* (Requested by DGP): on signature operation, ask user consent */
	if ((rv=acos5_64_ask_user_consent(card, user_consent_title, user_consent_message)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature", "User consent denied\n");
		return rv;
	}

	sc_apdu apdu; //                          CLAINSP1 P2               lc            apdu.data
	bytes2apdu(ctx, cast(immutable(ubyte)[])x"00 2A 9E 9A" ~ cast(ubyte)tmp_arr.length ~ tmp_arr,     apdu);
	apdu.flags = SC_APDU_FLAGS_NO_GET_RESP | (tmp_arr.length > 0xFF ? SC_APDU_FLAGS_CHAINING : 0LU);
	mixin transmit_apdu!("acos5_64_compute_signature");  if ((rv=transmit_apdu_do)<0) return rv;

	if (apdu.sw1 != 0x61) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
			"Didn't get clearance to call get_response\n");
		return rv=SC_ERROR_UNKNOWN;
	}

	uint received;
	size_t count;
	ubyte* p = out_;
	do {
		count = in_len - received; // here count is: 'not_received', what remains to be received; get_response truncates to max_recv_length 0X100
		if ((rv=iso_ops_ptr.get_response(card, &count, p)) < 0) { // 
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
				"get_response failed: rv: %d, count:%lu , \n", rv, count);
			return rv;
		}
		received += count; // now count is what actually got received from the preceding get_response call
		p        += count;
	} while (in_len > received && count>0); // receiving more than in_lenmax==512 would cause a crash here
/*
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"Output from compute_signature len: '%d' bytes:\n%s\n============================================================",
			received, sc_dump_hex(out_, received));
*/
	if (in_len != received)
		return rv=SC_ERROR_UNKNOWN;
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_compute_signature",
		"MESSAGE FROM PRIVATE KEY USAGE: Private key was successfully applied for signatur generation");

	return rv=cast(int)received;
}


private extern(C) int acos5_64_list_files(sc_card* card, ubyte* buf, size_t buflen)
{
  sc_apdu apdu;
  int rv;
  size_t count;
  ubyte* bufp = buf;
  int fno = 0;    /* current file index */

	sc_context* ctx = card.ctx;
	mixin (log!(q{"acos5_64_list_files"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_list_files",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_list_files",
				"returning with: %d\n", rv);
	}

	/* Check parameters. */
	if (!buf || (buflen < 8))
		return SC_ERROR_INVALID_ARGUMENTS;

	/*
	 * Use CARD GET INFO to fetch the number of files under the
	 * curently selected DF.
	 */
	sc_format_apdu(card, &apdu, SC_APDU_CASE_1, 0x14, 0x01, 0x00);
	apdu.cla = 0x80;
	if ((rv=sc_transmit_apdu(card, &apdu)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_list_files",
			"APDU transmit failed: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}
	if (apdu.sw1 != 0x90)
		return rv=SC_ERROR_INTERNAL;
	count = apdu.sw2;

	while (count--) {
		ub8 info; // acos will deliver 8 bytes: [FDB, DCB(always 0), FILE ID, FILE ID, SIZE or MRL, SIZE or NOR, SFI, LCSI]

		/* Truncate the scan if no more room left in output buffer. */
		if (buflen == 0)
			break;

		apdu = sc_apdu(); // apdu = apdu.init;
		sc_format_apdu(card, &apdu, SC_APDU_CASE_2_SHORT, 0x14, 0x02, fno++);
		with (apdu) {
			cla = 0x80;
			resp         = info.ptr;
			resplen = le = info.sizeof;
		}
		if ((rv=sc_transmit_apdu(card, &apdu)) < 0) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_list_files",
				"APDU transmit failed: %d (%s)\n", rv, sc_strerror(rv));
			return rv;
		}

		if (apdu.sw1 != 0x90 || apdu.sw2 != 0x00)
			return rv=SC_ERROR_INTERNAL;

		*bufp++ = info[2];
		*bufp++ = info[3];
		buflen -= 2;
	}

	return  rv=cast(int)(bufp - buf);
}

private extern(C) int acos5_64_check_sw(sc_card *card, uint sw1, uint sw2)
{
	/* intercept SW of pin_cmd ? */
	/* intercept SW 7.3.1. Get Card Info Identify Self? */
	int rv = SC_ERROR_UNKNOWN;
	sc_context* ctx = card.ctx;
	sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_check_sw",
		"called for: sw1 = 0x%02x, sw2 = 0x%02x\n", sw1, sw2);
//	mixin (log!(q{"acos5_64_check_sw"}, q{"called"})); //
	scope(exit) { 
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_check_sw",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_check_sw",
				"returning with: %d\n", rv);
	}

	if (sw1 == 0x90)
		return rv= (sw2==0x00 ? SC_SUCCESS : SC_ERROR_CARD_CMD_FAILED);
	else if (sw1 == 0x95U && sw2 == 0x40U) // this is a response to "Identify Self" and is okay for Version ACS ACOS5-64 v2.00/no error
		return rv=SC_SUCCESS;
	else if (sw1 == 0x61U /*&& sw2 == 0x40U*/)
		return rv=SC_SUCCESS;
	/* iso error */
	return rv=iso_ops_ptr.check_sw(card, sw1, sw2);
}

struct acos5_64_se_info {
////	iasecc_sdo_docp            docp;
	int                        reference;

	sc_crt[SC_MAX_CRTS_IN_SE]  crts;

	sc_file*                   df;
	acos5_64_se_info*          next;

	uint                       magic;
}

private int acos5_64_se_cache_info(sc_card* card, acos5_64_se_info* se) {
	sc_context* ctx = card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"acos5_64_se_cache_info"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_cache_info",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_cache_info",
				"returning with: %d\n", rv);
	}

	acos5_64_private_data* prv = cast(acos5_64_private_data*) card.drv_data;
	acos5_64_se_info* se_info  = cast(acos5_64_se_info*)calloc(1, acos5_64_se_info.sizeof);

	if (!se_info) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_cache_info", "SE info allocation error");
		return rv=SC_ERROR_OUT_OF_MEMORY;
	}
	memcpy(se_info, se, acos5_64_se_info.sizeof);

	if (card.cache.valid && card.cache.current_df) {
		sc_file_dup(&se_info.df, card.cache.current_df);
		if (se_info.df == null) {
			free(se_info);
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_cache_info", "Cannot duplicate current DF file");
			return rv=SC_ERROR_OUT_OF_MEMORY;
		}
	}

////	if ((rv=acos5_64_docp_copy(ctx, &se.docp, &se_info.docp)) < 0) {
////		free(se_info.df);
////		free(se_info);
////		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_cache_info", "Cannot make copy of DOCP");
////		return rv;
////	}

	if (!prv.se_info)
		prv.se_info = se_info;
	else {
		acos5_64_se_info* si;
		for (si = prv.se_info; si.next; si = si.next)
		{}
		si.next = se_info;
	}

	return rv;
}

private int acos5_64_se_get_info_from_cache(sc_card* card, acos5_64_se_info* se) {
	sc_context* ctx = card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"acos5_64_se_get_info_from_cache"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_info_from_cache",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_info_from_cache",
				"returning with: %d\n", rv);
	}

	acos5_64_private_data* prv = cast(acos5_64_private_data*)card.drv_data;
	acos5_64_se_info* si;

	for (si = prv.se_info; si; si = si.next) {
		if (si.reference != se.reference)
			continue;
		if (!(card.cache.valid && card.cache.current_df) && si.df)
			continue;
		if (card.cache.valid && card.cache.current_df && !si.df)
			continue;
		if (card.cache.valid && card.cache.current_df && si.df)
			if (memcmp(&card.cache.current_df.path, &si.df.path, sc_path.sizeof))
				continue;
		break;
	}

	if (!si)
		return rv=SC_ERROR_OBJECT_NOT_FOUND;

	memcpy(se, si, acos5_64_se_info.sizeof);

	if (si.df) {
		sc_file_dup(&se.df, si.df);
		if (se.df == null) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_info_from_cache", "Cannot duplicate current DF file");
			return rv=SC_ERROR_OUT_OF_MEMORY;
		}
	}

////	if ((rv=acos5_64_docp_copy(ctx, &si.docp, &se.docp)) < 0) {
////		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_info_from_cache", "Cannot make copy of DOCP");
////		return rv;
////	}
	return rv;
}

private int acos5_64_se_get_info(sc_card* card, acos5_64_se_info* se) {
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_se_get_info"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_info",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_info",
				"returning with: %d\n", rv);
	}
	

	if (se.reference > 0x0F/*IASECC_SE_REF_MAX*/)
		return rv=SC_ERROR_INVALID_ARGUMENTS;

	if ((rv=acos5_64_se_get_info_from_cache(card, se)) == SC_ERROR_OBJECT_NOT_FOUND)   {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_info",
			"No SE#%X info in cache, try to use 'GET DATA'", se.reference);
		if (rv == SC_ERROR_OBJECT_NOT_FOUND)
			return rv;
		
		if ((rv=acos5_64_se_cache_info(card, se)) < 0) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_info", "failed to put SE data into cache");
			return rv;
		}
	} // if ((rv=acos5_64_se_get_info_from_cache(card, se)) == SC_ERROR_OBJECT_NOT_FOUND)

	return rv;
}

private int acos5_64_se_get_crt(sc_card* card, acos5_64_se_info* se, sc_crt* crt) {
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_se_get_crt"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_crt",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_crt",
				"returning with: %d\n", rv);
	}

	if (!se || !crt)
		return rv=SC_ERROR_INVALID_ARGUMENTS;
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_crt",
		"CRT search template: %X:%X:%X, refs %X:%X:...", crt.tag, crt.algo, crt.usage, crt.refs[0], crt.refs[1]);

	for (int ii=0; ii<SC_MAX_CRTS_IN_SE && se.crts[ii].tag; ii++)   {
		if (crt.tag != se.crts[ii].tag)
			continue;
		if (crt.algo && crt.algo != se.crts[ii].algo)
			continue;
		if (crt.usage && crt.usage != se.crts[ii].usage)
			continue;
		if (crt.refs[0] && crt.refs[0] != se.crts[ii].refs[0])
			continue;

		memcpy(crt, &se.crts[ii], sc_crt.sizeof);

		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_crt",
			"acos5_64_se_get_crt() found CRT with refs %X:%X:...", se.crts[ii].refs[0], se.crts[ii].refs[1]);
		return rv=SC_SUCCESS;
	}

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_se_get_crt", "iasecc_se_get_crt() CRT is not found");
	return rv=SC_ERROR_DATA_OBJECT_NOT_FOUND;
}

private int acos5_64_get_chv_reference_from_se(sc_card* card, int* se_reference) {
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_get_chv_reference_from_se"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_chv_reference_from_se",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_chv_reference_from_se",
				"returning with: %d\n", rv);
	}

	if (!se_reference)
		return rv=SC_ERROR_INVALID_ARGUMENTS;

	acos5_64_se_info  se;
	se.reference = *se_reference;

	if ((rv=acos5_64_se_get_info(card, &se)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_chv_reference_from_se", "get SE info error\n");
		return rv;
	}

	sc_crt crt;
	crt.tag   = 0xA4; // IASECC_CRT_TAG_AT;
	crt.usage = 0x08; // IASECC_UQB_AT_USER_PASSWORD;

	if ((rv=acos5_64_se_get_crt(card, &se, &crt)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_get_chv_reference_from_se", "Cannot get 'USER PASSWORD' authentication template\n");
		return rv;
	}

	if (se.df)
		sc_file_free(se.df);
	return rv=crt.refs[0];
}

/**
 * Implementation for Card_Ctl() card driver operation.
 *
 * This command provides access to non standard functions provided by
 * this card driver, as defined in cardctl.h
 *
 * @param card Pointer to card driver structure
 * @param request Operation requested
 * @param data where to get data/store response
 * @return SC_SUCCESS if ok; else error code
 * @see cardctl.h
 *
 * TODO: wait for GET_CARD_INFO generic cardctl to be implemented in opensc
 */
private extern(C) int acos5_64_card_ctl(sc_card* card, c_ulong request, void* data) {
	if (card == null || card.ctx == null)
		return SC_ERROR_INVALID_ARGUMENTS;
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_NOT_SUPPORTED;
	mixin (log!(q{"acos5_64_card_ctl"}, q{"called"})); //
//	sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_card_ctl", "request=%lu\n", request);
	scope(exit) {
		if (rv <= 0)
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_card_ctl",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_card_ctl",
				"returning with: %d\n", rv);
	}

	if (data == null)
		return rv=SC_ERROR_INVALID_ARGUMENTS;

	final switch (cast(SC_CARDCTL)request) {
		case SC_CARDCTL_GENERIC_BASE, SC_CARDCTL_ERASE_CARD, SC_CARDCTL_GET_DEFAULT_KEY, SC_CARDCTL_LIFECYCLE_GET
				, SC_CARDCTL_PKCS11_INIT_TOKEN, SC_CARDCTL_PKCS11_INIT_PIN:
			return rv; // SC_ERROR_NOT_SUPPORTED
		case SC_CARDCTL_LIFECYCLE_SET:
			SC_CARDCTRL_LIFECYCLE lcsi =  cast(SC_CARDCTRL_LIFECYCLE)(*cast(int*)data); // Life Cycle Status Integer
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_card_ctl",
				"request=SC_CARDCTL_LIFECYCLE_SET with *data: %d\n", lcsi);
			final switch (lcsi) {
				case SC_CARDCTRL_LIFECYCLE_ADMIN:
				{
					sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_card_ctl",
						"### FAKING SO LOGIN ### request=SC_CARDCTL_LIFECYCLE_SET with *data==SC_CARDCTRL_LIFECYCLE_ADMIN\n");
					sc_pin_cmd_data data_so;
					with (data_so) {
						cmd           = SC_PIN_CMD.SC_PIN_CMD_VERIFY;
						flags         = SC_PIN_CMD_NEED_PADDING;
						pin_type      = SC_AC_CHV;
						pin_reference = 0x0333;
					}
					int tries_left;
					if ((rv=acos5_64_pin_cmd(card, &data_so, &tries_left)) != SC_SUCCESS)
						return rv;
					else
						return rv=SC_ERROR_NOT_SUPPORTED;//SC_SUCCESS;
				}
				case SC_CARDCTRL_LIFECYCLE_USER, SC_CARDCTRL_LIFECYCLE_OTHER:
					return rv; // SC_ERROR_NOT_SUPPORTED
			}
		case SC_CARDCTL_GET_SERIALNR: /* call card to obtain serial number */
			return rv=acos5_64_get_serialnr(card, cast(sc_serial_number*) data);
		case SC_CARDCTL_GET_SE_INFO:
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_card_ctl",
				"CMD SC_CARDCTL_GET_SE_INFO: sdo_class prozentX"/*, sdo.sdo_class*/);
			return rv=acos5_64_se_get_info(card, cast(acos5_64_se_info*)data);
		case SC_CARDCTL_GET_CHV_REFERENCE_IN_SE:
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_card_ctl",
				"CMD SC_CARDCTL_GET_CHV_REFERENCE_IN_SE");
			return rv=acos5_64_get_chv_reference_from_se(card, cast(int*)data);
	}
}

/*
 * The reason for this function is that OpenSC doesn't set any
 * Security Attribute Tag in the FCI upon file creation if there
 * is no file->sec_attr. I set the file->sec_attr to a format
 * understood by the applet (ISO 7816-4 tables 16, 17 and 20).
 * The iso7816_create_file will then set this as Tag 86 - Sec.
 * Attr. Prop. Format.
 * The applet will then be able to set and enforce access rights
 * for any file created by OpenSC. Without this function, the
 * applet would not know where to enforce security rules and
 * when.
 *
 * Note: IsoApplet currently only supports a "onepin" option.
 *
 * Format of the sec_attr: 8 Bytes:
 *  7      - ISO 7816-4 table 16 or 17
 *  6 to 0 - ISO 7816-4 table 20
 */
private extern(C) int acos5_64_create_file(sc_card* card, sc_file* file)
{
	/*
	 * @brief convert an OpenSC ACL entry to the security condition
	 * byte used by this driver.
	 *
	 * Used by acos5_64_create_file to parse OpenSC ACL entries
	 * into ISO 7816-4 Table 20 security condition bytes.
	 *
	 * @param entry The OpenSC ACL entry.
	 *
	 * @return The security condition byte. No restriction (0x00)
	 *         if unknown operation.
	 */
	ubyte acos5_64_acl_to_security_condition_byte(const(sc_acl_entry)* entry)
	{
		if (!entry)
			return 0x00;
		switch(entry.method) {
			case SC_AC_CHV:
				return 0x90;
			case SC_AC_NEVER:
				return 0xFF;
			case SC_AC_NONE:
			default:
				return 0x00;
		}
	}

	int rv = SC_SUCCESS;
	sc_context* ctx = card.ctx;
	mixin (log!(q{"acos5_64_create_file"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_create_file",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_create_file",
				"returning with: %d\n", rv);
	}

	if (file.sec_attr_len == 0) {
		ub8 access_buf;
		int[8] idx = [
			0, /* Reserved. */
			SC_AC_OP.SC_AC_OP_DELETE_SELF, /* b6 */
			SC_AC_OP.SC_AC_OP_LOCK,        /* b5   (Terminate) */
			SC_AC_OP.SC_AC_OP_ACTIVATE,    /* b4 */
			SC_AC_OP.SC_AC_OP_DEACTIVATE,  /* b3 */
			0, /* Preliminary */  /* b2 */
			0, /* Preliminary */  /* b1 */
			0  /* Preliminary */  /* b0 */
		];

		if (file.type == SC_FILE_TYPE_DF) {
			const(int)[3] df_idx = [ /* These are the SC operations. */
				SC_AC_OP.SC_AC_OP_CREATE_DF,   /* b2 */
				SC_AC_OP.SC_AC_OP_CREATE_EF,   /* b1 */
				SC_AC_OP.SC_AC_OP_DELETE       /* b0   (Delete Child) */
			];
			idx[5..8] = df_idx[];
		}
		else {  /* EF */
			const(int)[3] ef_idx = [
				SC_AC_OP.SC_AC_OP_WRITE,       /* b2 */ // file.type == ? 0: 
				SC_AC_OP.SC_AC_OP_UPDATE,      /* b1 */
				SC_AC_OP.SC_AC_OP_READ         /* b0 */
			];
			idx[5..8] = ef_idx[];
		}
		/* Now idx contains the operation identifiers.
		 * We now search for the OPs. */
		access_buf[0] = 0xFF; /* A security condition byte is present for every OP. (Table 19) */
		for (int i=1; i<8; ++i) {
			const(sc_acl_entry)* entry;
			entry = sc_file_get_acl_entry(file, idx[i]);
			access_buf[i] = acos5_64_acl_to_security_condition_byte(entry);
		}

		if ((rv=sc_file_set_sec_attr(file, access_buf.ptr, 8)) < 0) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_create_file", "Error adding security attribute.");
			return rv;
		}
	}

	return rv=iso_ops_ptr.create_file(card, file);
}


/**
 * This function first calls the iso7816.c process_fci() for any other FCI
 * information and then updates the ACL of the OpenSC file struct according
 * to the FCI (from the isoapplet.
 
 6F 1E  83 02 41 03  88 01 03  8A 01 05  82 06 1C 00 00 30 00 05  8C 08 7F FF FF 03 03 01 03 01  AB 00
 */
private extern(C) int acos5_64_process_fci(sc_card* card, sc_file* file, const(ubyte)* buf, size_t buflen)
{

	void file_add_acl_entry(sc_file *file, int op, uint SCB) // checked against card-acos5_64.c  OPENSC_loc
	{
		uint method, keyref = SC_AC_KEY_REF_NONE;

		switch (SCB) {
			case 0x00:
				method = SC_AC.SC_AC_NONE;
				break;
			case 0xFF:
				method = SC_AC.SC_AC_NEVER;
				break;
			case 0x41: .. case 0x4E: // Force the use of Secure Messaging and at least one condition specified in the SE-ID of b3-b0
				// TODO
				method = SC_AC.SC_AC_SCB;
				keyref = SCB & 0x0F;
				break;
			case 0x01: .. case 0x0C: // acos allows 0x0E, but opensc is limited to 0x0C==SC_MAX_CRTS_IN_SE;  At least one condition specified in the SE ID of b3-b0
				goto case;  // continues to the next case
			case 0x81: .. case 0x8C: // acos allows 0x0E, but opensc is limited to 0x0C==SC_MAX_CRTS_IN_SE;  All conditions         specified in the SE ID of b3-b0
				method = SC_AC.SC_AC_SEN; //SC_AC.SC_AC_CHV;
				keyref = SCB & 0x0F;
				break;
			default:
				method = SC_AC.SC_AC_UNKNOWN;
				break;
		}
		sc_file_add_acl_entry(file, op, method, keyref);
	}

	import core.cpuid : hasPopcnt;
	import core.bitop : /* _popcnt, */ popcnt; // GDC doesn't know _popcnt

	size_t taglen, plen = buflen;
	const(ubyte)* tag = null, p = buf;
	int rv;
	sc_context* ctx = card.ctx;
	mixin (log!(q{"acos5_64_process_fci"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_process_fci",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_process_fci",
				"returning with: %d\n", rv);
	}

	// iso_ops_ptr.process_fci does a nice job, leaving some refinements etc. for this function
	if ((rv = iso_ops_ptr.process_fci(card, file, buf, buflen)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_process_fci",
			"error parsing fci: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}

	if (!file)
		return rv=SC_SUCCESS;

	file.sid = 0;
	ubyte FDB;
	/* catch up on everything, iso_ops_ptr.process_fci did omit: SE-file FDB (0x1C), tags 0x8C and 0xAB */

	tag = sc_asn1_find_tag(ctx, p, plen, 0x82, &taglen);
	if (tag && taglen > 0 && taglen <= 6 /*&& file.type!=SC_FILE_TYPE_WORKING_EF*/ && file.type!=SC_FILE_TYPE_DF) {
		if (!canFind(/*[0x3F, 0x38, 0x01, 0x02, 0x04, 0x06, 0x09, 0x0A, 0x0C, 0x1C]*/ [EnumMembers!EFDB], tag[0]))
			return rv=SC_ERROR_INVALID_ASN1_OBJECT;
		FDB = tag[0]; // 82 06  1C 00 00 30 00 05
		switch (FDB) {
			case CHV_EF, Symmetric_key_EF:
//				file.type = SC_FILE_TYPE_BSO;
//				sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_process_fci", "  type (corrected): BSO EF CHV or Symmetric-key");
				break;
			case RSA_Key_EF:
				if ((integral2ub!2(file.id)[1] & 0xF0) == 0xF0) { // privat? the public key is no BSO
//					file.type = SC_FILE_TYPE_BSO;
//					sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_process_fci", "  type (corrected): BSO EF RSA private");
				}
				break;
			case SE_EF:
//				type = "internal EF";
				file.type = SC_FILE_TYPE_INTERNAL_EF; // refinement might be SC_FILE_TYPE_INTERNAL_SE_EF
				sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_process_fci", "  type (corrected): proprietary EF SecurityEnvironment"); // SE-file  // FDB == 0x1C
				break;
			default:	
				break;
		}
		if (taglen>=5 /*&& taglen <= 6*/) {//FDB+DCB+00h+MRL+NOR or FDB+DCB+00h+MRL+00h+NOR;  MRL:maximum record length (<=255); in case of linear variable, there may be less bytes in a record than MRL
			file.record_length = tag[3];        // ubyte MRL // In case of fixed-length or cyclic EF
			file.record_count  = tag[taglen-1]; // ubyte NOR // Valid, if not transparent EF or DF
		}
	}

	tag = sc_asn1_find_tag(ctx, p, plen, 0x8C, &taglen); // e.g. 8C 08 7F FF FF 01 01 01 01 FF; taglen==8, x"7F FF FF 01 01   01 01 FF"
/+ +/
	ubyte AM; // Access Mode Byte (AM) 
	ub8   SC; // initialized with SC_AC_NONE;

	if (tag && taglen > 0) {
		AM = *tag++;
		if (1+ (/*hasPopcnt? _popcnt(AM) :*/ popcnt(AM)) != taglen)
			return rv=SC_ERROR_INVALID_ASN1_OBJECT;

		foreach (i, ref b; SC)
			if (AM & (0b1000_0000 >>> i))
				b = *tag++;
	}
/+ +/
//		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_process_fci",
//			"2sc_asn1_find_tag(ctx, p, plen, 0x8C, &taglen): 0x8C %d %02X %s\n", taglen, AM, sc_dump_hex(SC.ptr, 8));
	file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_DELETE_SELF,     SC[1]);
	file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_LOCK,            SC[2]); // Terminate
	file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_REHABILITATE,    SC[3]); // Activate
//file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_ACTIVATE,        SC[3]);
	file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_INVALIDATE,      SC[4]); // Deactivate
//file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_DEACTIVATE,      SC[4]);

	final switch (cast(SC_FILE_TYPE)file.type) {
		case SC_FILE_TYPE_DF:
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_CREATE_DF,   SC[5]);
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_CREATE_EF,   SC[6]);
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_CREATE,      SC[6]); // What to specify here? CREATE_EF or CREATE_DF? Currently return CREATE_EF
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_DELETE,      SC[7]); // Delete Child 
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_SELECT,      SC_AC_NONE);
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_LIST_FILES,  SC_AC_NONE);
			break;
		case SC_FILE_TYPE_INTERNAL_EF:
			final switch (cast(EFDB)FDB) {
				case SE_EF:  // potentially as own SC_FILE_TYPE in case SC_FILE_TYPE_INTERNAL_SE_EF:
					file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_CRYPTO,                     SC[5]); //  MSE Restore
					break;
				case CHV_EF:
					break;
				case RSA_Key_EF, Symmetric_key_EF:
					file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_CRYPTO,                     SC[5]); //  MSE/PSO Commands
					if (FDB==Symmetric_key_EF) {
						file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_PSO_DECRYPT,              SC[5]);
						file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_PSO_ENCRYPT,              SC[5]);
						file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_PSO_COMPUTE_CHECKSUM,     SC[5]);
						file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_PSO_VERIFY_CHECKSUM,      SC[5]);
					}
					else if (FDB==RSA_Key_EF) {
						file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_GENERATE,                 SC[5]);
						if (SC[7]==0xFF) { // then assume it's the private key
							file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_PSO_DECRYPT,            SC[5]);
							file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_PSO_COMPUTE_SIGNATURE,  SC[5]);
						}
						else {
							file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_PSO_ENCRYPT,            SC[5]);
							file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_PSO_VERIFY_SIGNATURE,   SC[5]);
						}
					}
					break;
				// all other non-internal_EF FDBs are not involved, just mentioned for final switch usage
				case Transparent_EF, Linear_Fixed_EF, Linear_Variable_EF, Cyclic_EF, DF, MF: break;
			}
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_UPDATE,          SC[6]);
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_WRITE,           SC[6]); //###
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_DELETE,          SC[1]); //### synonym SC_AC_OP_ERASE, points to SC_AC_OP_DELETE_SELF
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_READ,            SC[7]);
			break;
		case SC_FILE_TYPE_WORKING_EF:
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_UPDATE,  SC[6]);
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_WRITE,   SC[6]); //###
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_DELETE,  SC[1]); // synonym SC_AC_OP_ERASE, points to SC_AC_OP_DELETE_SELF
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_READ,    SC[7]);
			break;
		case SC_FILE_TYPE_BSO: // BSO (Base Security Object) BSO contains data that must never go out from the card, but are essential for cryptographic operations, like PINs or Private Keys
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_CRYPTO,          SC[5]); //  MSE/PSO Commands
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_UPDATE,          SC[6]);
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_WRITE,           SC[6]); //###
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_DELETE,          SC[1]); //### synonym SC_AC_OP_ERASE, points to SC_AC_OP_DELETE_SELF
			file_add_acl_entry (file, SC_AC_OP.SC_AC_OP_READ,            SC[7]);
			break;
	} // final switch (cast(SC_FILE_TYPE)file.type)
/+ +/
	/* do some post processing, if file.size if record based files determined by iso7816_process_fci is zero; read from tag 0x82, if available */
	if (file.size == 0) {
		tag = sc_asn1_find_tag(ctx, p, plen, 0x82, &taglen);
		if (tag != null && taglen >= 5 && taglen <= 6) {
			ubyte MRL = tag[3], NOR = tag[taglen-1];
			file.size = MRL * NOR;
		}
	}

	return rv=SC_SUCCESS;
}

private extern(C) int acos5_64_construct_fci(sc_card* card, const(sc_file)* file, ubyte* out_, size_t* outlen) {

	int acl_to_ac_byte(sc_card* card, const(sc_acl_entry)* e) {
		if (e == null)
			return SC_ERROR_OBJECT_NOT_FOUND;

		switch (e.method) {
		case SC_AC.SC_AC_NONE:
			return 0x00; // LOG_FUNC_RETURN(card.ctx, EPASS2003_AC_MAC_NOLESS | EPASS2003_AC_EVERYONE);
		case SC_AC.SC_AC_NEVER:
			return 0xFF; // LOG_FUNC_RETURN(card.ctx, EPASS2003_AC_MAC_NOLESS | EPASS2003_AC_NOONE);
//		case SC_AC.SC_AC_SCB:
//			return 0x02;
		case SC_AC.SC_AC_CHV:
			return 0x01;
//		case SC_AC.SC_AC_SEN:
//			return 0x03;
		default:
			return 0x00; // LOG_FUNC_RETURN(card.ctx, EPASS2003_AC_MAC_NOLESS | EPASS2003_AC_USER);
		}
	}

	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_construct_fci"}, q{"called"}));
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_construct_fci",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_construct_fci",
				"returning with: %d\n", rv);
	}

	ubyte* p = out_;
	ubyte[64] buf;

	if (*outlen < 2)
		return rv=SC_ERROR_BUFFER_TOO_SMALL;

	*p++ = 0x62;
	++p;
	if ((file.type == SC_FILE_TYPE.SC_FILE_TYPE_WORKING_EF  && file.ef_structure == SC_FILE_EF_TRANSPARENT) ||
			(file.type == SC_FILE_TYPE.SC_FILE_TYPE_INTERNAL_EF && file.ef_structure == EFDB.RSA_Key_EF)) {
		buf[0..2] = integral2ub!2(file.size)[0..2];
		sc_asn1_put_tag(0x80, buf.ptr, 2, p, *outlen - (p - out_), &p); // 80h 02h  Transparent File Size in bytes
	}

	if (file.type == SC_FILE_TYPE.SC_FILE_TYPE_DF) {
		buf[0] = 0x38;
		buf[1] = 0x00;
		sc_asn1_put_tag(0x82, buf.ptr, 2, p, *outlen - (p - out_), &p); // 82h 02h  FDB + DCB
	}
	else if (file.type == SC_FILE_TYPE.SC_FILE_TYPE_WORKING_EF) {
		buf[0] = file.ef_structure & 7;
		if (file.ef_structure == SC_FILE_EF_TRANSPARENT) {
			buf[1] = 0x00;
			sc_asn1_put_tag(0x82, buf.ptr, 2, p, *outlen - (p - out_), &p); // 82h 02h  FDB + DCB
		}
	}
	else if (file.type == SC_FILE_TYPE.SC_FILE_TYPE_INTERNAL_EF) {
		if (file.ef_structure == EFDB.RSA_Key_EF) {
			buf[0] = 0x09;
			buf[1] = 0x00;
		}
		else
			return SC_ERROR_NOT_SUPPORTED;
		sc_asn1_put_tag(0x82, buf.ptr, 2, p, *outlen - (p - out_), &p);
	}

	buf[0] = (file.id >>> 8) & 0xFF;
	buf[1] = file.id & 0xFF;
	sc_asn1_put_tag(0x83, buf.ptr, 2, p, *outlen - (p - out_), &p);

	buf[0] = 0x01;
	sc_asn1_put_tag(0x8A, buf.ptr, 1, p, *outlen - (p - out_), &p);

	ub8 ops = [ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF ];
	{
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_construct_fci", "SC_FILE_ACL");
		if (file.type == SC_FILE_TYPE_DF) {
			ops[0] = SC_AC_OP.SC_AC_OP_LIST_FILES;
			ops[1] = SC_AC_OP.SC_AC_OP_CREATE;
			ops[3] = SC_AC_OP.SC_AC_OP_DELETE;
		}
		else if (file.type == SC_FILE_TYPE_WORKING_EF) {
			if (file.ef_structure == SC_FILE_EF_TRANSPARENT) {
				ops[0] = SC_AC_OP.SC_AC_OP_READ;
				ops[1] = SC_AC_OP.SC_AC_OP_UPDATE;
//				ops[3] = SC_AC_OP_DELETE;
			}
			else if (file.ef_structure == SC_FILE_EF_LINEAR_FIXED
					|| file.ef_structure == SC_FILE_EF_LINEAR_VARIABLE) {
				ops[0] = SC_AC_OP.SC_AC_OP_READ;
				ops[1] = SC_AC_OP.SC_AC_OP_UPDATE;
				ops[2] = SC_AC_OP.SC_AC_OP_WRITE;
//				ops[3] = SC_AC_OP_DELETE;
			}
			else {
				return SC_ERROR_NOT_SUPPORTED;
			}
		}
		else if (file.type == SC_FILE_TYPE_BSO) {
			ops[0] = SC_AC_OP.SC_AC_OP_UPDATE;
			ops[3] = SC_AC_OP.SC_AC_OP_DELETE;
		}
		else if (file.type == SC_FILE_TYPE_INTERNAL_EF) {
			if (file.ef_structure == EFDB.RSA_Key_EF) {
				ops[0] = SC_AC_OP.SC_AC_OP_READ;
				ops[1] = SC_AC_OP.SC_AC_OP_UPDATE;
//				ops[2] = SC_AC_OP.SC_AC_OP_GENERATE;
				ops[3] = SC_AC_OP.SC_AC_OP_INVALIDATE;
				ops[4] = SC_AC_OP.SC_AC_OP_REHABILITATE;
//				ops[5] = SC_AC_OP.SC_AC_OP_LOCK;
//				ops[6] = SC_AC_OP.SC_AC_OP_DELETE;
			}
		}
		else {
			return SC_ERROR_NOT_SUPPORTED;
		}

		for (uint ii = 0; ii < ops.length-1; ++ii) {
			const(sc_acl_entry)* entry;

			buf[ii] = 0xFF;
			if (ops[ii] == 0xFF)
				continue;
			entry = sc_file_get_acl_entry(file, ops[ii]);

			if ((rv=acl_to_ac_byte(card, entry)) < 0) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_construct_fci", "Invalid ACL");
				return rv;
			}

			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_construct_fci",
				"entry(%p), entry.method(%#X), rv(%#X) \n", entry, entry.method, rv);

			buf[ii] = cast(ubyte)rv;
			if (ii==0 && file.type == SC_FILE_TYPE_INTERNAL_EF && file.ef_structure == EFDB.RSA_Key_EF && (integral2ub!2(file.id)[1] & 0xF0)==0x30)
				buf[ii] = SC_AC_NONE;
		}

		buf[ops.length-1] = 0x7F;
		ub8 buf2 = array(retro(buf[0..8]));
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_construct_fci",
			"AM +7 SC bytes: %p\n", sc_dump_hex(buf2.ptr, buf2.length));
		sc_asn1_put_tag(0x8C, buf2.ptr, buf2.length, p, *outlen - (p - out_), &p);

	}
	out_[1] = cast(ubyte)(p - out_ - 2);

	*outlen = p - out_;

	return rv=SC_SUCCESS;
}


private extern(C) int acos5_64_pin_cmd(sc_card *card, sc_pin_cmd_data *data, int *tries_left) {
	sc_context* ctx = card.ctx;
	int rv;
	mixin (log!(q{"acos5_64_pin_cmd"}, q{"called"}));
	scope(exit) {
		if (rv <= 0)
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_cmd",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_cmd",
			"returning with: %d\n", rv);
	}

/* */
	with (*data)
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_cmd",
			"sc_pin_cmd_data 1-4: cmd(%u), flags(%u), pin_type(%u), pin_reference(0x%02X)\n", cmd, flags, pin_type, pin_reference);
	if (data.pin1.prompt && strlen(data.pin1.prompt))
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_cmd",
			"prompt: %s\n", data.pin1.prompt);
	with (data.pin1)	
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_cmd",
			"sc_pin_cmd_data.pin1: min_length(%lu), max_length(%lu), stored_length(%lu), encoding(%u)\n", min_length, max_length, stored_length, encoding);
/* */

	final switch (cast(SC_PIN_CMD)data.cmd) {
	case SC_PIN_CMD_VERIFY: /*0*/
		final switch (cast(SC_AC)data.pin_type) {
		case SC_AC_CHV:
			if (data.pin_reference == 0x0333 ) {
				ubyte[8] dataX = [0x38, 0x37, 0x36, 0x35, 0x34, 0x33, 0x32, 0x31];
				sc_apdu apdu;
				sc_format_apdu(card, &apdu, SC_APDU_CASE_3_SHORT, 0x20, 0x00, 0x01);
				apdu.datalen = apdu.lc = dataX.length;
				apdu.data              = dataX.ptr;
				if ((rv = sc_transmit_apdu(card, &apdu)) < 0) {
					sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_cmd",
						"APDU transmit failed: %d (%s)\n", rv, sc_strerror(rv));
					return rv;
				}
				if ((rv = sc_check_sw(card, apdu.sw1, apdu.sw2)) < 0) {
					sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_cmd",
						"PIN cmd failed: %d (%s)\n", rv, sc_strerror(rv));
					return rv;
				}
			}
			else {
				sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_cmd",
					"Next:     Call   to   iso7816.c:iso7816_pin_cmd\n");
				data.pin_reference |= 0x80;
				/* ISO7816 implementation works */
				rv = iso_ops_ptr.pin_cmd(card, data, tries_left);
				sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_cmd",
					"Previous: Return from iso7816.c:iso7816_pin_cmd\n");
			}
			break;
		case SC_AC_AUT:
		/* 'AUT' key is the transport PIN and should have reference '0' */
			rv = (data.pin_reference ? SC_ERROR_INVALID_ARGUMENTS : iso_ops_ptr.pin_cmd(card, data, tries_left));
			break;
		case SC_AC_NONE, SC_AC_TERM, SC_AC_PRO, SC_AC_SYMBOLIC, SC_AC_SEN, SC_AC_SCB, SC_AC_IDA, SC_AC_UNKNOWN, SC_AC_NEVER:
			rv = SC_ERROR_INVALID_ARGUMENTS;
			break;
		}
		break;
	case SC_PIN_CMD_CHANGE: /*1*/
		if (data.pin_type == SC_AC_AUT)
			rv = SC_ERROR_INS_NOT_SUPPORTED;
		else
			rv = acos5_64_pin_change(card, data, tries_left);
		break;
	case SC_PIN_CMD_UNBLOCK: /*2*/
		if (data.pin_type != SC_AC_CHV)
			rv = SC_ERROR_INS_NOT_SUPPORTED;
		else {
			/* 1. step: verify the puk */
			/* ISO7816 implementation works */
//			if ((rv = iso_ops_ptr.pin_cmd(card, data, tries_left)) < 0)
//				return rv;

//			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_cmd", "We are about to call acos5_64_pin_unblock_change\n");
			/* 2, step: unblock and change the pin */
			rv = acos5_64_pin_unblock_change(card, data, tries_left);
		}
		break;
	case SC_PIN_CMD_GET_INFO: /*3*/
		rv = acos5_64_pin_get_policy(card, data);//iasecc_pin_get_policy(card, data);
		break;
	}
	
	return rv;//acos5_64_check_sw(card, apdu.sw1, apdu.sw2);
}

private int acos5_64_pin_get_policy(sc_card *card, sc_pin_cmd_data *data)
{
	sc_context* ctx = card.ctx;
	int rv;
	mixin (log!(q{"acos5_64_pin_get_policy"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_get_policy",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_get_policy",
			"returning with: %d\n", rv);
	}
//		data->flags=0;// what shall be done here? Ask for the remaining tries of User PIN
	sc_apdu apdu;
	sc_format_apdu(card, &apdu, SC_APDU_CASE_1, 0x20, 0x00, data.pin_reference | 0x80);
	/* send apdu */
	if ((rv = sc_transmit_apdu(card, &apdu)) < 0) {
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_get_policy",
			"APDU transmit failed: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}

	if (apdu.sw1 != 0x63 || (apdu.sw2 & 0xFFFFFFF0U) != 0xC0)
		return rv=SC_ERROR_INTERNAL;
	rv = SC_SUCCESS;
	if (data.pin_reference < 0x80) {
		data.pin1.len           = 8; /* set to -1 to get pin from pin pad FIXME Must be changed if user has installed a pin pad and wants to use this instead of keyboard */
		data.pin1.min_length    = 4; /* min length of PIN */
		data.pin1.max_length    = 8; /* max length of PIN */
		data.pin1.stored_length = 8; /* stored length of PIN */
		data.pin1.encoding      = SC_PIN_ENCODING_ASCII; /* ASCII-numeric, BCD, etc */
		data.pin1.pad_length    = 0; /* filled in by the card driver */
		data.pin1.pad_char      = 0xFF;
		data.pin1.offset = 5; /* PIN offset in the APDU */
		data.pin1.length_offset = 5;
		data.pin1.length_offset = 0; /* Effective PIN length offset in the APDU */

		data.pin1.max_tries  =  8; /* Used for signaling back from SC_PIN_CMD_GET_INFO */ /* assume: 8 as factory setting; max allowed number of retries is unretrievable with proper file access condition NEVER read */
		data.pin1.tries_left =  apdu.sw2 & 0x0F; /* Used for signaling back from SC_PIN_CMD_GET_INFO */
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_get_policy",
			"Tries left for User PIN : %d\n", data.pin1.tries_left);
	}
	return rv;
}

private int acos5_64_pin_change(sc_card *card, sc_pin_cmd_data *data, int *tries_left)
{
	sc_context* ctx = card.ctx;
	sc_apdu apdu;
	uint reference = data.pin_reference;
	ubyte[0x100] pin_data;
	int rv;

	sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_change", "called\n");
	sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_change",
		"Change PIN(ref:%i,type:0x%X,lengths:%i/%i)", reference, data.pin_type, data.pin1.len, data.pin2.len);

	if (!data.pin1.data && data.pin1.len) {
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_change",
			"Invalid PIN1 arguments: %d (%s)\n", SC_ERROR_INVALID_ARGUMENTS, sc_strerror(SC_ERROR_INVALID_ARGUMENTS));
		return SC_ERROR_INVALID_ARGUMENTS;
	}

	if (!data.pin2.data && data.pin2.len) {
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_change",
			"Invalid PIN2 arguments: %d (%s)\n", SC_ERROR_INVALID_ARGUMENTS, sc_strerror(SC_ERROR_INVALID_ARGUMENTS));
		return SC_ERROR_INVALID_ARGUMENTS;
	}

	rv = iso_ops_ptr.pin_cmd(card, data, tries_left); // verifies pin1
	sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_change",
		"(SC_PIN_CMD_CHANGE) old pin (pin1) verification returned %i", rv);
	if (rv < 0) {
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_change",
			"PIN verification error: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}

	if (data.pin2.data)
		memcpy(pin_data.ptr /* + data.pin1.len*/, data.pin2.data, data.pin2.len);

	sc_format_apdu(card, &apdu, SC_APDU_CASE_3_SHORT, 0x24, 0x01, reference);
	apdu.data = pin_data.ptr;
	apdu.datalen = /*data.pin1.len + */data.pin2.len;
	apdu.lc = apdu.datalen;

	if ((rv = sc_transmit_apdu(card, &apdu)) < 0) {
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_change",
			"APDU transmit failed: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}
	if ((rv = sc_check_sw(card, apdu.sw1, apdu.sw2)) < 0) {
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_change",
			"PIN cmd failed: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}

	if (rv <= 0)
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_change",
			"returning with: %d (%s)\n", rv, sc_strerror(rv));
	else
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_change",
			"returning with: %d\n", rv);

	return rv;
}

private int acos5_64_pin_unblock_change(sc_card *card, sc_pin_cmd_data *data, int *tries_left)
{
	sc_context* ctx = card.ctx;
	sc_apdu apdu;
	uint reference = data.pin_reference;
	ubyte[0x100] pin_data;
	int rv = SC_SUCCESS;//SC_ERROR_INS_NOT_SUPPORTED;

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_unblock_change", "called\n");
	if (!data.pin1.data || data.pin1.len==0) { // no puk available or empty
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_unblock_change",
			"Invalid PUK arguments: %d (%s)\n", SC_ERROR_INVALID_ARGUMENTS, sc_strerror(SC_ERROR_INVALID_ARGUMENTS));
		return SC_ERROR_INVALID_ARGUMENTS;
	}
	
	if (data.pin2.data && data.pin2.len>0 && (data.pin2.len < 4 || data.pin2.len > 8)) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_unblock_change",
			"Invalid PIN2 length: %d (%s)\n", SC_ERROR_INVALID_PIN_LENGTH, sc_strerror(SC_ERROR_INVALID_PIN_LENGTH));
		return SC_ERROR_INVALID_PIN_LENGTH; 
	}	

	/* Case 3 short APDU, 5 bytes+?: ins=2C p1=00/01 p2=pin-reference lc=? le=00 */
	sc_format_apdu(card, &apdu, SC_APDU_CASE_3_SHORT, 0x2C, 0x00, reference);
	memcpy(pin_data.ptr, data.pin1.data, data.pin1.len);
	if (!data.pin2.data || data.pin2.len==0) { // do solely unblocking
		apdu.p1 = 0x01;
		apdu.lc = data.pin1.len;
	}
	else { // do unblocking + changing pin (new-pin is in pin2)
		apdu.lc = data.pin1.len + data.pin2.len;
		memcpy(pin_data.ptr+data.pin1.len, data.pin2.data, data.pin2.len);
	}
	apdu.datalen = apdu.lc;
	apdu.data = pin_data.ptr;

	if ((rv = sc_transmit_apdu(card, &apdu)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_unblock_change",
			"APDU transmit failed: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}
	if ((rv = sc_check_sw(card, apdu.sw1, apdu.sw2)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_unblock_change",
			"Unblock pin cmd failed: %d (%s)\n", rv, sc_strerror(rv));
		return rv;
	}
	
	if (rv <= 0)
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_unblock_change",
			"returning with: %d (%s)\n", rv, sc_strerror(rv));
	else
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pin_unblock_change",
			"returning with: %d\n", rv);

	return rv;
}

private extern(C) int acos5_64_read_public_key(sc_card* card, uint algorithm, sc_path* path, uint key_reference, uint modulus_length, ubyte** buf, size_t* buflen)
{
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_NOT_SUPPORTED;
	mixin (log!(q{"acos5_64_read_public_key"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_read_public_key",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_read_public_key",
				"returning with: %d\n", rv);
	}

	sc_apdu      apdu;
	immutable(uint)  N = modulus_length/8; /* key modulus_length in byte */
	auto             MHB = immutable(ubyte) ((N>>>8) & 0xFF); /* with modulus length N as 2 byte value: Modulus High Byte of N, or its the zero byte for MLB with MSB set */
	immutable(ubyte) MLB = N & 0xFF; /* with modulus length N as 2 byte value: Modulus Low Byte of N */
	ubyte* key_in,  pkey_in;  /* key_in  keeps position; length of internal format:	 5 + 16(e) + N(n/8) */
	ubyte* key_out, pkey_out; /* key_out keeps position; length of asn.1 format:		11 + 16(e) + N(n/8) */
	immutable(uint) le_accumul = N + 21;
	immutable(uint) len_out    = N + 27;
	uint count = 0;

	assert(path != null && buf != null);
	if (algorithm != SC_ALGORITHM_RSA)
		return rv=SC_ERROR_NOT_SUPPORTED;

	rv = sc_select_file(card, path, null);

	/* Case 2 short APDU, 5 bytes: ins=CA p1=xx p2=yy lc=0000 le=00zz */
	sc_format_apdu(card, &apdu, SC_APDU_CASE_2_SHORT, 0xCA, 0x00, 0x00);
	apdu.cla = 0x80;
	apdu.resplen = le_accumul;
	apdu.le = le_accumul>SC_READER_SHORT_APDU_MAX_SEND_SIZE ? SC_READER_SHORT_APDU_MAX_SEND_SIZE : le_accumul;
	pkey_in = key_in = cast(ubyte*)malloc(le_accumul);

	while (le_accumul > count && count <= 0xFFFF-apdu.le) {
		apdu.p1   = cast(ubyte) (count>>>8 & 0xFF);
		apdu.p2   = count & SC_READER_SHORT_APDU_MAX_SEND_SIZE;
		apdu.resp = key_in + count;
		/* send apdu */
		rv = sc_transmit_apdu(card, &apdu);
		if (rv < 0) {
			free(key_in);
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_read_public_key",
				"APDU transmit failed");
			return rv;
		}
		if (apdu.sw1 != 0x90 || apdu.sw2 != 0x00) {
			free(key_in);
			return rv=SC_ERROR_INTERNAL;
		}
		count += apdu.le;
		if (le_accumul-count < SC_READER_SHORT_APDU_MAX_SEND_SIZE)
			apdu.le = le_accumul-count;
	}

	pkey_out = key_out = cast(ubyte*) malloc(len_out);
	if (key_out == null) {
		free(key_in);
		return rv=SC_ERROR_OUT_OF_MEMORY;
	}

	/* 0x021B = 512+16 + "30 820217 02 820201 00" + "0210" for 4096 bit key */
	*pkey_out++ = 0x30;
	*pkey_out++ = 0x82;
	*pkey_out++ = MHB;
	*pkey_out++ = cast(ubyte) (MLB + 23); /*always is < 0xFF */

	*pkey_out++ = 0x02;
	*pkey_out++ = 0x82;
	*pkey_out++ = MHB;
	*pkey_out++ = cast(ubyte) (MLB + 1);
	*pkey_out++ = 0x00; /* include zero byte */

	pkey_in = key_in + 21;
	memcpy(pkey_out, pkey_in, N);
	pkey_out += N;
	*pkey_out++ = 0x02;
	*pkey_out++ = 0x10;
	pkey_in = key_in + 5;
	memcpy(pkey_out, pkey_in, 16);

	*buflen = len_out;
	*buf = key_out;
	rv = SC_SUCCESS;

	free(key_in);
	/* key_out didn't get free'd: TODO check this */
	return rv;
}

private extern(C) int acos5_64_pkcs15_init_card(sc_profile* profile, sc_pkcs15_card* p15card)
{
	sc_context* ctx = p15card.card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_pkcs15_init_card"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_init_card",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_init_card",
				"returning with: %d\n", rv);
	}

	sc_path    path;
	sc_file*   file;
	ubyte[256] rbuf;

	p15card.tokeninfo.flags = SC_PKCS15_TOKEN_PRN_GENERATION /*0| SC_PKCS15_TOKEN_EID_COMPLIANT*/;

	rv = sc_card_ctl(p15card.card, SC_CARDCTL_GET_SERIALNR, rbuf.ptr);

	sc_format_path("3F00", &path);
	rv = sc_select_file(p15card.card, &path, &file);

	if (file)
		sc_file_free(file);

	return rv;
}

private extern(C) int acos5_64_pkcs15_select_pin_reference(sc_profile*, sc_pkcs15_card* p15card, sc_pkcs15_auth_info*)
{
	sc_context* ctx = p15card.card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"acos5_64_pkcs15_select_pin_reference"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_select_pin_reference",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_select_pin_reference",
				"returning with: %d\n", rv);
	}
	return rv; 
}

/*
 * Select a key reference
 */
private extern(C) int acos5_64_pkcs15_select_key_reference(sc_profile*, sc_pkcs15_card* p15card,
			sc_pkcs15_prkey_info* key_info)
{
	sc_context* ctx = p15card.card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"acos5_64_pkcs15_select_key_reference"}, q{"called"})); //
	scope(exit)
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_select_key_reference",
			"returning (key reference %i) with: %d (%s)\n", key_info.key_reference, rv, sc_strerror(rv));

	if (key_info.key_reference > ACOS5_64_CRYPTO_OBJECT_REF_MAX)
		return rv=SC_ERROR_INVALID_ARGUMENTS;

	if (key_info.key_reference < ACOS5_64_CRYPTO_OBJECT_REF_MIN)
		key_info.key_reference = ACOS5_64_CRYPTO_OBJECT_REF_MIN;

	return rv=SC_SUCCESS; 
}

/* Generate the private key on card */
private extern(C) int acos5_64_pkcs15_create_key(sc_profile*, sc_pkcs15_card* p15card, sc_pkcs15_object*)
{
	sc_context* ctx = p15card.card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"acos5_64_pkcs15_create_key"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_create_key",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_create_key",
				"returning with: %d\n", rv);
	}
	return rv; 
}

private extern(C) int acos5_64_pkcs15_store_key(sc_profile*, sc_pkcs15_card* p15card,
			sc_pkcs15_object*,
			sc_pkcs15_prkey*)
{
	sc_context* ctx = p15card.card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"acos5_64_pkcs15_store_key"}, q{"called"}));
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_store_key",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_store_key",
				"returning with: %d\n", rv);
	}
	return rv; 
}

private ubyte encodedRSAbitLen(const uint bitLenDec) pure nothrow @nogc @safe
{
	import std.algorithm.comparison : clamp;
	return  cast(ubyte)((clamp(bitLenDec+8,512U,4096U)/256U)*2U);
}

@safe
unittest {
  import std.stdio;
  assert(encodedRSAbitLen( 511) == 0x04);
  assert(encodedRSAbitLen( 512) == 0x04); // defined, lowerLimit
  assert(encodedRSAbitLen( 759) == 0x04);
  assert(encodedRSAbitLen( 767) == 0x06);
  assert(encodedRSAbitLen( 768) == 0x06); // defined
// for each increment in by 256 -> increment by 0x02
  assert(encodedRSAbitLen(3840) == 0x1E); // defined
  assert(encodedRSAbitLen(4095) == 0x20);
  assert(encodedRSAbitLen(4096) == 0x20); // defined, upperLimit
  assert(encodedRSAbitLen(4100) == 0x20);
  writeln("PASSED: encodedRSAbitLen");
}

private int new_file(sc_profile* profile, sc_pkcs15_card* p15card, sc_pkcs15_object* p15object, uint otype, sc_file** out_)
{
	sc_context* ctx = p15card.card.ctx;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"new_file"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "new_file",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "new_file",
				"returning with: %d\n", rv);
	}

	assert(p15object.type == SC_PKCS15_TYPE_PRKEY_RSA);
	assert(otype == SC_PKCS15_TYPE_PRKEY_RSA || otype == SC_PKCS15_TYPE_PUBKEY_RSA);

	sc_pkcs15_prkey_info* key_info = cast(sc_pkcs15_prkey_info*)p15object.data;
	uint keybits = ((cast(uint)key_info.modulus_length+8U)/256)*256;

	uint structure = 0xFFFFFFFF;
	structure = EFDB.RSA_Key_EF;

	uint modulusBytes = keybits/8; //                                        Read
	sc_file* file = sc_file_new();
	with (file) {
		path = key_info.path;
		if (otype == SC_PKCS15_TYPE_PUBKEY_RSA)
			path.value[path.len-1] &= 0x3F;
		type = SC_FILE_TYPE.SC_FILE_TYPE_INTERNAL_EF;
		ef_structure = EFDB.RSA_Key_EF;
		size = 5 + (otype == SC_PKCS15_TYPE_PRKEY_RSA? modulusBytes/2*5 : modulusBytes+16); // CRT for SC_PKCS15_TYPE_PRKEY_RSA
		id = ub22integral(path.value[path.len-2..path.len]);
	}

	if      (otype == SC_PKCS15_TYPE_PRKEY_RSA)
		rv=sc_file_add_acl_entry(file, SC_AC_OP.SC_AC_OP_READ,       SC_AC_NEVER, SC_AC_KEY_REF_NONE);
	else if (otype == SC_PKCS15_TYPE_PUBKEY_RSA)
		rv=sc_file_add_acl_entry(file, SC_AC_OP.SC_AC_OP_READ,       SC_AC_NONE,  SC_AC_KEY_REF_NONE);

	rv=sc_file_add_acl_entry(file, SC_AC_OP.SC_AC_OP_UPDATE,       SC_AC_CHV,   SC_AC_KEY_REF_NONE);
	rv=sc_file_add_acl_entry(file, SC_AC_OP.SC_AC_OP_CRYPTO,       SC_AC_CHV,   SC_AC_KEY_REF_NONE);
	rv=sc_file_add_acl_entry(file, SC_AC_OP.SC_AC_OP_GENERATE,     SC_AC_CHV,   SC_AC_KEY_REF_NONE);

	rv=sc_file_add_acl_entry(file, SC_AC_OP.SC_AC_OP_INVALIDATE,   SC_AC_CHV/*SC_AC_TERM*/,  SC_AC_KEY_REF_NONE);
	rv=sc_file_add_acl_entry(file, SC_AC_OP.SC_AC_OP_REHABILITATE, SC_AC_CHV/*SC_AC_PRO*/,   SC_AC_KEY_REF_NONE);
	rv=sc_file_add_acl_entry(file, SC_AC_OP.SC_AC_OP_LOCK,         SC_AC_CHV/*SC_AC_SEN*/,   SC_AC_KEY_REF_NONE);
	rv=sc_file_add_acl_entry(file, SC_AC_OP.SC_AC_OP_DELETE,       SC_AC_CHV/*SC_AC_SCB*/,   SC_AC_KEY_REF_NONE);

	rv=sc_file_add_acl_entry(file, SC_AC_OP.SC_AC_OP_GENERATE,     SC_AC_CHV,   SC_AC_KEY_REF_NONE);

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "new_file",
		"file size %i; ef type %i/%i; id %04X; path_len %i; file path: %s\n",
		file.size, file.type, file.ef_structure, file.id, file.path.len, sc_print_path(&(file.path)));

	*out_ = file;
	return rv=SC_SUCCESS;
}

private extern(C) int acos5_64_pkcs15_generate_key(sc_profile* profile, sc_pkcs15_card* p15card, sc_pkcs15_object* p15object, sc_pkcs15_pubkey* p15pubkey)
{
	sc_card* card   = p15card.card;
	sc_context* ctx = card.ctx;
	sc_file* file;
	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"acos5_64_pkcs15_generate_key"}, q{"called"}));
	scope(exit) {
		if (file)
			sc_file_free(file);
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
				"returning with: %d\n", rv);
	}
//////////
	sc_pkcs15_prkey_info* key_info = cast(sc_pkcs15_prkey_info*)p15object.data;
	uint keybits = ((cast(uint)key_info.modulus_length+8U)/256)*256;

/////////
	if (p15object.type != SC_PKCS15_TYPE_PRKEY_RSA) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key", "Failed: Only RSA is supported");
		return rv=SC_ERROR_NOT_SUPPORTED;
	}
	/* Check that the card supports the requested modulus length */
	if (sc_card_find_rsa_alg(card, keybits) == null) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key", "Failed: Unsupported RSA key size");
		return rv=SC_ERROR_INVALID_ARGUMENTS;
	}
/* TODO Think about other checks or possibly refuse to genearate keys if file access rights are wrong */

	/* allocate key object */
	if ((rv=new_file(profile, p15card, p15object, SC_PKCS15_TYPE_PRKEY_RSA, &file)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key", "create key: failed to allocate new key object");
		if (file)
			sc_file_free(file);
		return rv;
	}

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
		"private key path: %s", sc_print_path(&file.path));

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
		"private key_info path: %s", sc_print_path(&(key_info.path)));

	/* delete, if existant */
	if ((rv=sc_pkcs15init_authenticate(profile, p15card, file, SC_AC_OP_DELETE)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key", "generate key: pkcs15init_authenticate(SC_AC_OP_DELETE) failed");
		if (rv == SC_ERROR_FILE_NOT_FOUND) {}
		else {
			if (file)
				sc_file_free(file);
			return rv;
		}
	}
	if (rv != SC_ERROR_FILE_NOT_FOUND)
		rv = sc_delete_file(card, &file.path);

	/* create */
	if ((rv=sc_pkcs15init_create_file(profile, p15card, file)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key", "create key: failed to create private key file on card");
		if (file)
			sc_file_free(file);
		return rv;
	}
/* */
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
		"Have to generate RSA key pair with keybits %i; ID: %s and path: %s", keybits, sc_pkcs15_print_id(&key_info.id), sc_print_path(&key_info.path));

	sc_file* tfile;
	sc_path path = key_info.path;
	path.len -= 2;

	if ((rv=sc_select_file(card, &path, &tfile)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
			"generate key: no private object DF");
		if (file)
			sc_file_free(file);
		if (tfile)
			sc_file_free(tfile);
		return rv;
	}

	sc_file* pukf;
	if ((rv=new_file(profile, p15card, p15object, SC_PKCS15_TYPE_PUBKEY_RSA, &pukf)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
			"generate key: create temporary pukf failed\n");
		if (pukf)
			sc_file_free(pukf);
		if (file)
			sc_file_free(file);
		if (tfile)
			sc_file_free(tfile);
		return rv;
	}

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
		"public key size %i; ef type %i/%i; id %04X; path: %s",
		 pukf.size, pukf.type, pukf.ef_structure, pukf.id,
		 sc_print_path(&pukf.path));

	/* if exist, delete */
	if ((rv=sc_select_file(p15card.card, &pukf.path, null)) == SC_SUCCESS) {
		if ((rv=sc_pkcs15init_authenticate(profile, p15card, pukf, SC_AC_OP_DELETE)) < 0) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
				"generate key - pubkey: pkcs15init_authenticate(SC_AC_OP_DELETE) failed");
			if (pukf)
				sc_file_free(pukf);
			if (file)
				sc_file_free(file);
			if (tfile)
				sc_file_free(tfile);
			return rv;
		}

		if ((rv=sc_pkcs15init_delete_by_path(profile, p15card, &pukf.path)) != SC_SUCCESS) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
				"generate key: failed to delete existing key file\n");
			if (pukf)
				sc_file_free(pukf);
			if (file)
				sc_file_free(file);
			if (tfile)
				sc_file_free(tfile);
			return rv;
		}
	}
	/* create */
	if ((rv=sc_pkcs15init_create_file(profile, p15card, pukf)) != SC_SUCCESS) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
			"generate key: pukf create file failed\n");
		if (pukf)
			sc_file_free(pukf);
		if (file)
			sc_file_free(file);
		if (tfile)
			sc_file_free(tfile);
		return rv;
	}

	if ((rv=sc_pkcs15init_authenticate(profile, p15card, pukf, SC_AC_OP_UPDATE)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
			"generate key - pubkey: pkcs15init_authenticate(SC_AC_OP_UPDATE) failed");
		if (pukf)
			sc_file_free(pukf);
		if (file)
			sc_file_free(file);
		if (tfile)
			sc_file_free(tfile);
		return rv;
	}

///////////////////
/* TODO file is selected twice (in sc_pkcs15init_authenticate as well) */
	if ((rv=sc_select_file(card, &key_info.path, &file)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
			"Cannot generate key: failed to select key file");
		return rv;
	}
	if ((rv=sc_pkcs15init_authenticate(profile, p15card, file, SC_AC_OP_GENERATE)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
			"No authorisation to generate private key");
		if (file)
			sc_file_free(file);
		return rv;
	}
	{ // set SE for private key usage
		sc_security_env env;
		env.flags = SC_SEC_ENV_FILE_REF_PRESENT;
		env.operation = 5; /*SC_SEC_OPERATION_SIGN*/ // case 5: // my encoding for SC_SEC_GENERATE_RSAKEYS_PRIVATE
		assert(key_info.path.len >= 2);
		env.file_ref.len = 2;
		env.file_ref.value[0..2] = key_info.path.value[key_info.path.len-2..key_info.path.len];
//		env.file_ref.value[1] = key_info.path[key_info.path.len-1];
		if ((rv=acos5_64_set_security_env(card, &env, 0)) < 0) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
				"Cannot generate key: failed to set SE for private key file");
			return rv;
		}
	}
	{ // set SE for public key usage; by convention prkey file id's are 41Fx and corresponding pubkey file id's are 413x 
		sc_security_env env;
		env.flags = SC_SEC_ENV_FILE_REF_PRESENT;
		env.operation = 6; /*SC_SEC_OPERATION_SIGN*/ // case 6: // my encoding for SC_SEC_GENERATE_RSAKEYS_PUBLIC
/* TODO how to get public key file id for known private key file id ? */
		env.file_ref.len = 2;
		env.file_ref.value[0..2] = key_info.path.value[key_info.path.len-2..key_info.path.len];
		env.file_ref.value[1] &= 0x3F;
		if ((rv=acos5_64_set_security_env(card, &env, 0)) < 0) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
				"Cannot generate key: failed to set SE for public key file");
			return rv;
		}
	}

	// 00 46 00 00  02 2004
	ubyte[2] sbuf = [encodedRSAbitLen(keybits), ERSA_Key_type.CRT_for_Decrypting_only]; // always CRT
	if (key_info.usage & SC_PKCS15_PRKEY_USAGE_SIGN)
		sbuf[1] = ERSA_Key_type.CRT_for_Signing_and_Decrypting;

	sc_apdu apdu;
	sc_format_apdu(card, &apdu, SC_APDU_CASE_3_SHORT, 0x46, 0, 0);
	apdu.lc = apdu.datalen = sbuf.length;
	apdu.data = sbuf.ptr;

	if ((rv=sc_transmit_apdu(card, &apdu)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
			"%s: APDU transmit failed", sc_strerror(rv));
		return rv;
	}

	if ((rv=sc_check_sw(card, apdu.sw1, apdu.sw2)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
			"%s: Card returned error", sc_strerror(rv));
		return rv;
	}

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
		"p15object.type: %04x\n", p15object.type);
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
		"p15object.label: %s\n", p15object.label.ptr);
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
		"p15object.flags: %08x\n", p15object.flags);
	if (p15object.auth_id.value.ptr != null)
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
			"p15object.auth_id.value: %s\n", sc_dump_hex(p15object.auth_id.value.ptr, p15object.auth_id.len));
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_generate_key",
		"keybits: %u\n", keybits);

	/* Keypair generation -> collect public key info */
		if (p15pubkey != null) with (p15pubkey) {
			algorithm = SC_ALGORITHM_RSA;
			u.rsa.modulus.len = keybits / 8;
			u.rsa.modulus.data = cast(ubyte*)malloc(u.rsa.modulus.len);
			ubyte[3] DEFAULT_PUBEXPONENT = [0x01, 0x00, 0x01];
			u.rsa.exponent.len = DEFAULT_PUBEXPONENT.length;
			u.rsa.exponent.data = cast(ubyte*)malloc(DEFAULT_PUBEXPONENT.length);
			memcpy(u.rsa.exponent.data, DEFAULT_PUBEXPONENT.ptr, DEFAULT_PUBEXPONENT.length);
		}

	return rv=SC_SUCCESS; 
}

/*
 * Encode private/public key
 * These are used mostly by the Cryptoflex/Cyberflex drivers.
 */
private extern(C) int acos5_64_pkcs15_encode_private_key(sc_profile* profile, sc_card* card,
				sc_pkcs15_prkey_rsa*,
				ubyte* , size_t*, int) {
	sc_context* ctx = card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"acos5_64_pkcs15_encode_private_key"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_encode_private_key",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_encode_private_key",
				"returning with: %d\n", rv);
	}
	return rv; 
}

private extern(C) int acos5_64_pkcs15_encode_public_key(sc_profile* profile, sc_card* card,
				sc_pkcs15_prkey_rsa*,
				ubyte* , size_t*, int) {
	sc_context* ctx = card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"acos5_64_pkcs15_encode_public_key"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_encode_public_key",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_encode_public_key",
				"returning with: %d\n", rv);
	}
	return rv; 
}

private extern(C) int acos5_64_pkcs15_delete_object(sc_profile* profile, sc_pkcs15_card* p15card,
			sc_pkcs15_object*, const(sc_path)* path) {
	sc_context* ctx = p15card.card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"acos5_64_pkcs15_delete_object"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_delete_object",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_delete_object",
				"returning with: %d\n", rv);
	}
	return rv=sc_pkcs15init_delete_by_path(profile, p15card, path);
}

private extern(C) int acos5_64_pkcs15_emu_store_data(sc_pkcs15_card* p15card, sc_profile* profile, sc_pkcs15_object*,
				sc_pkcs15_der*, sc_path*) {
	sc_context* ctx = p15card.card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"acos5_64_pkcs15_emu_store_data"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_emu_store_data",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_emu_store_data",
				"returning with: %d\n", rv);
	}
	return rv; 
}

private extern(C) int acos5_64_pkcs15_sanity_check(sc_profile* profile, sc_pkcs15_card* p15card) {
	sc_context* ctx = p15card.card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"acos5_64_pkcs15_sanity_check"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_sanity_check",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_pkcs15_sanity_check",
				"returning with: %d\n", rv);
	}
	return rv; 
}


uba /* <-OctetStringBigEndian*/ integral2ub(uint storage_bytes)(size_t integral)
	if (storage_bytes<=size_t.sizeof)
{
	uba result; 
	foreach (i; 0..storage_bytes)
		result ~= cast(ubyte)(integral >>> 8*(storage_bytes-1-i) & 0xFF); // precedence: () *  >>>  &
	return result;
}

/** Take a byte stream as coming form the token and convert to an integral value
Most often, the byte stream has to be interpreted as big-endian (The most significant byte (MSB) value, is at the lowest address (position in stream). The other bytes follow in decreasing order of significance)
currently used in new_file and unittest only
*/
ushort ub22integral(in uba ub2) {
/* TODO make this general */
	if (ub2.length!=2)
		return 0;
	return  (ub2[0] << 8) | ub2[1];
}

//@safe
unittest {
	import std.stdio;
//	writeln("size_t.sizeof: ", size_t.sizeof);
	ubyte[2] ub2 = [0x41, 0x03];
	assert(ub22integral([0x41, 0x03]) == 0x4103);
	writeln("PASSED: ub22integral");

	const integralVal = 0xFFEEDDCCBBAA9988UL;
	assert(equal(integral2ub!8(integralVal), [0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA, 0x99, 0x88][]));
	writeln("PASSED: integral2ub!8");
version(LittleEndian) {
	assert(equal(integral2ub!4(integralVal),                         [0xBB, 0xAA, 0x99, 0x88][]));
	writeln("PASSED: integral2ub!4");
}
}

version(ENABLE_ACOS5_64_UI/*ENABLE_DNIE_UI*/) {
	/**
	 * To handle user interface routines
	 */
	struct ui_context_t {
		int     user_consent_enabled;
		string  user_consent_app;
	}
//	alias  ui_context_t = ui_context;

	ref ui_context_t get_acos5_64_ui_ctx(sc_card* card) {
		return (cast(acos5_64_private_data*)card.drv_data).ui_ctx;
	}

/** default user consent program (if required) */
string USER_CONSENT_CMD = "/usr/bin/pinentry";

/** Messages used on user consent procedures */
immutable(char)* user_consent_title   = "Request for permit: Generation of digital signature"; // 
//immutable(char)* user_consent_title   = "Erlaubnisanfrage zur Erstellung digitale Signatur/Unterschrift"; // 

immutable(char)* user_consent_message ="A token's secret/private RSA-key shall be used to generate and hand over Your digital signature!\nDo You agree?\n\n(Don't agree if You didn't expect this!)";
//immutable(char)* user_consent_message ="Ein geheimer/privater RSA-Schlüssel des Token soll zur Erstellung/Aushändigung Ihrer digitalen Signatur/Unterschrift benutzt werden! Stimmen Sie zu?";
//immutable(char)* user_consent_message ="Está a punto de realizar una firma electrónica con su clave de FIRMA del DNI electrónico. ¿Desea permitir esta operación?";

private int acos5_64_get_environment(sc_card* card, ui_context_t* ui_context) {
	scconf_block** blocks;
	scconf_block*  blk;
	sc_context*    ctx = card.ctx;
	/* set default values */
	ui_context.user_consent_app = USER_CONSENT_CMD;
	ui_context.user_consent_enabled = 1;
	/* look for sc block in opensc.conf */
	foreach (elem; ctx.conf_blocks) {
		if (elem == null)
			break;
		blocks = scconf_find_blocks(ctx.conf, elem, "card_driver", "acos5_64");
		if (!blocks)
			continue;
		blk = blocks[0];
		free(blocks);
		if (blk == null)
			continue;
		/* fill private data with configuration parameters */
		ui_context.user_consent_app =	/* def user consent app is "pinentry" */
			scconf_get_str (blk, "user_consent_app", USER_CONSENT_CMD.toStringz /*the default*/).fromStringz.idup;
		ui_context.user_consent_enabled =	/* user consent is enabled by default */
			scconf_get_bool(blk, "user_consent_enabled", 1);
	}
	return SC_SUCCESS;
} // acos5_64_get_environment

/**
 * Messages used on pinentry protocol
 */
const(char)*[] user_consent_msgs = ["SETTITLE", "SETDESC", "CONFIRM", "BYE" ];

version(Posix) {
/**
 * Ask for user consent.
 *
 * Check for user consent configuration,
 * Invoke proper gui app and check result
 *
 * @param card pointer to sc_card structure
 * @param title Text to appear in the window header
 * @param text Message to show to the user
 * @return SC_SUCCESS on user consent OK , else error code
 */
private int acos5_64_ask_user_consent(sc_card* card, const(char)* title, const(char)* message) {
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_INTERNAL;	/* by default error :-( */
	mixin (log!(q{"acos5_64_ask_user_consent"}, q{"called"})); //
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_ask_user_consent",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_ask_user_consent",
				"returning with: %d\n", rv);
	}

version(Posix) { // should be for Linux only  #include <sys/stat.h>
	import core.sys.posix.sys.types;
	import core.sys.posix.sys.stat;
	import core.sys.posix.unistd;
	import core.sys.posix.stdio : fdopen;
	import core.stdc.stdio;
	import core.stdc.string : strstr;
//	import core.sys.linux.fcntl;
	pid_t   pid;
	FILE*   fin;
	FILE*   fout;	/* to handle pipes as streams */
	stat_t  st_file;	/* to verify that executable exists */
	int[2]  srv_send;	/* to send data from server to client */
	int[2]  srv_recv;	/* to receive data from client to server */
	char[1024] outbuf;	/* to compose and send messages */
	char[1024] buf;		/* to store client responses */
	int n = 0;		/* to iterate on to-be-sent messages */
}

	string msg;	/* to mark errors */

	if (card == null || card.ctx == null)
		return rv=SC_ERROR_INVALID_ARGUMENTS;

	if (title==null || message==null)
		return rv=SC_ERROR_INVALID_ARGUMENTS;

	if (get_acos5_64_ui_ctx(card).user_consent_enabled == 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_ask_user_consent", "User Consent is disabled in configuration file");
		return rv=SC_SUCCESS;
	}

	/* check that user_consent_app exists. TODO: check if executable */
	rv = stat(get_acos5_64_ui_ctx(card).user_consent_app.toStringz, &st_file);
	if (rv != 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_ask_user_consent",
			"Invalid pinentry application: %s\n", get_acos5_64_ui_ctx(card).user_consent_app.toStringz);
		return rv=SC_ERROR_INVALID_ARGUMENTS;
	}
	/* just a simple bidirectional pipe+fork+exec implementation */
	/* In a pipe, xx[0] is for reading, xx[1] is for writing */
	if (pipe(srv_send) < 0) {
		msg = "pipe(srv_send)";
		goto do_error;
	}
	if (pipe(srv_recv) < 0) {
		msg = "pipe(srv_recv)";
		goto do_error;
	}

	pid = fork();
	switch (pid) {
	case -1:		/* error  */
		msg = "fork()";
		goto do_error;
	case 0:		/* child  */
		/* make our pipes, our new stdin & stderr, closing older ones */
		dup2(srv_send[0], STDIN_FILENO);	/* map srv send for input */
		dup2(srv_recv[1], STDOUT_FILENO);	/* map srv_recv for output */
		/* once dup2'd pipes are no longer needed on client; so close */
		close(srv_send[0]);
		close(srv_send[1]);
		close(srv_recv[0]);
		close(srv_recv[1]);
		/* call exec() with proper user_consent_app from configuration */
		/* if ok should never return */
		execlp(get_acos5_64_ui_ctx(card).user_consent_app.toStringz, get_acos5_64_ui_ctx(card).user_consent_app.toStringz, cast(char*)null);

		rv = SC_ERROR_INTERNAL;
		msg = "execlp() error";	/* exec() failed */
		goto do_error;
	default:		/* parent */
		/* Close the pipe ends that the child uses to read from / write to
		 * so when we close the others, an EOF will be transmitted properly.
		 */
		close(srv_send[0]);
		close(srv_recv[1]);
		/* use iostreams to take care on newlines and text based data */
		fin = fdopen(srv_recv[0], "r");
		if (fin == null) {
			msg = "fdopen(in)";
			goto do_error;
		}
		fout = fdopen(srv_send[1], "w");
		if (fout == null) {
			msg = "fdopen(out)";
			goto do_error;
		}
		/* read and ignore first line */
		fflush(stdin);
		for (n = 0; n<4; n++) {
			char* pt;
			memset(outbuf.ptr, 0, outbuf.sizeof);
			if (n==0) snprintf(outbuf.ptr,1023,"%s %s\n",user_consent_msgs[0],title);
			else if (n==1) snprintf(outbuf.ptr,1023,"%s %s\n",user_consent_msgs[1],message);
			else snprintf(outbuf.ptr,1023,"%s\n",user_consent_msgs[n]);
			/* send message */
			fputs(outbuf.ptr, fout);
			fflush(fout);
			/* get response */
			memset(buf.ptr, 0, buf.sizeof);
			pt=fgets(buf.ptr, buf.sizeof - 1, fin);
			if (pt==null) {
				rv = SC_ERROR_INTERNAL;
				msg = "fgets() Unexpected IOError/EOF";
				goto do_error;
			}
			if (strstr(buf.ptr, "OK") == null) {
				rv = SC_ERROR_NOT_ALLOWED;
				msg = "fail/cancel";
				goto do_error;
			}
		}
	}			/* switch */
	/* arriving here means signature has been accepted by user */
	rv = SC_SUCCESS;
	msg = null;

do_error:
	/* close out channel to force client receive EOF and also die */
	if (fout != null) fclose(fout);
	if (fin != null) fclose(fin);
	if (msg != null)
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "acos5_64_ask_user_consent", "%s\n", msg.toStringz);

	return rv;
} // acos5_64_ask_user_consent
} // version(Posix)

} // version(ENABLE_ACOS5_64_UI)

/**
OS2IP converts an octet string to a nonnegative integer.
   Input:  X octet string to be converted

   Output:  x corresponding nonnegative integer

This is usually done by acos for RSA operations
The interpretation of OS2IP's input is that of big-endian 
acos operates the same, expects an octet string `OctetString` where OctetString[0] is the most significant byte (highest importance for value of resulting BIGNUM)
*/
BIGNUM* OS2IP(uba OctetStringBigEndian)
out (result) { assert(!BN_is_negative(result)); }
body {
	BIGNUM* res = BN_new();
	BIGNUM* a   = BN_new();
	BIGNUM* b   = BN_new();
	if (res == null || a == null || b == null)
		return null;

	BN_zero(res);
	const int xLen = cast(int)OctetStringBigEndian.length;
	foreach (i; 0..xLen) {
		/*int*/ BN_set_word(a, OctetStringBigEndian[i]);
		/*int*/ BN_lshift  (b, a, 8*(xLen-1 -i));
		/*int*/ BN_add     (res, res, b);
	}
	BN_free(b);
	BN_free(a);
	return res;
}

version(PATCH_OPENSSL_BINDING_BN_ULONG) {

uba /* <-OctetStringBigEndian*/ I2OSP(BIGNUM* x, int xLen /* intended length of the resulting octet string */)
in { assert(!BN_is_negative(x)); }
body {
	uba res;
	if (BN_num_bytes(x) > xLen)
		return res;
	foreach (i_chunk; 0..x.top)
		res ~= integral2ub!(BN_ULONG.sizeof)(x.d[i_chunk]);

	return res;
}
} // version(PATCH_OPENSSL_BINDING_BN_ULONG)

unittest {
	import std.stdio;

	ubyte[4] zeros = [0x00, 0x00, 0x00, 0x00];
	ubyte[4] os    = [0x0A, 0x0B, 0xC0, 0xD0];
	BIGNUM* res = OS2IP(os);
	assert(BN_get_word(res)==0x0A0BC0D0); // thus unpatched, don't use this externally for more than ubyte[4], and use it for version(LittleEndian) only
	writeln("PASSED: OS2IP");

version(PATCH_OPENSSL_BINDING_BN_ULONG) {
	uba os2 = I2OSP(res, cast(int)BN_ULONG.sizeof);
	BN_free(res);
version(X86)
	assert(equal(os2, os[]));
else // X86_64 or more general any (64 bit processor) system where openssl defines BIGNUM's storage array underlying type (ulong) as having BN_BITS2 = 64
	assert(equal(os2, (zeros~os)[]));
	writeln("PASSED: I2OSP");
	import deimos.openssl.bio : BIO_snprintf;
	import deimos.openssl.bn;

	ulong num = 285212672;
	int normalInt = 5;
	char[120] buf;
	BIO_snprintf(buf.ptr, buf.length, "My number is %d bytes wide and its value is %lu. A normal number is %d.", num.sizeof, num, normalInt);
//	writeln("BIO_snprintf buf first:  ", buf.ptr.fromStringz);
	buf = buf.init;
	num = 0xFFEEDDCCBBAA9988;
	BIO_snprintf(buf.ptr, buf.length, BN_DEC_FMT1, num);
//	writeln("BIO_snprintf buf second: ", buf.ptr.fromStringz);

	buf = buf.init;
	BIO_snprintf(buf.ptr, buf.length, BN_DEC_FMT2, num);
//	writeln("BIO_snprintf buf third:  ", buf.ptr.fromStringz);
	stdout.flush();
}
}

const(sc_asn1_entry)[4]  c_asn1_acos5_64_sm_data_object = [
	sc_asn1_entry( "encryptedData", SC_ASN1_OCTET_STRING,	SC_ASN1_CTX | 7,   SC_ASN1_OPTIONAL),
	sc_asn1_entry( "commandStatus", SC_ASN1_OCTET_STRING,	SC_ASN1_CTX | 0x19 ),
	sc_asn1_entry( "ticket",        SC_ASN1_OCTET_STRING,	SC_ASN1_CTX | 0x0E ),
	sc_asn1_entry()
];

void sm_incr_ssc(ref ub8 ssc) {
	if(ssc[7] == 0xFF && ssc[6] == 0xFF) {
		ssc[6] = 0x00;
		ssc[7] = 0x00;
		return;
	}
	if(ssc[7] == 0xFF) {
		ssc[6]++;
		ssc[7] = 0x00;
	}
	else
		ssc[7]++;
}

int sm_acos5_64_decode_card_data(sc_context* ctx, sm_info* info, sc_remote_data *rdata, ubyte* out_, size_t out_len) {
	sm_cwa_session*   session_data = &info.session.cwa;
	sc_asn1_entry[4]  asn1_acos5_64_sm_data_object = [sc_asn1_entry(), sc_asn1_entry(), sc_asn1_entry(), sc_asn1_entry()]; //GDC-issue with init
	sc_remote_apdu*   rapdu;// = null;
	int               rv, offs;// = 0;

//	int rv = SC_ERROR_UNKNOWN;
	mixin (log!(q{"sm_acos5_64_decode_card_data"}, q{"called"})); //
	mixin log_scope_exit!("sm_acos5_64_decode_card_data"); 
	scope(exit)
		log_scope_exit_do();

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_decode_card_data",
		"decode answer() rdata length %i, out_ length %i", rdata.length, out_len);
	for (rapdu = rdata.data; rapdu; rapdu = rapdu.next)   {
//		ubyte* decrypted;
		ubyte[2*SC_MAX_APDU_BUFFER_SIZE] decrypted;
		size_t decrypted_len = decrypted.length;
		ubyte[SC_MAX_APDU_BUFFER_SIZE] resp_data;
		size_t resp_len = resp_data.length;
		ubyte[2] status;// = {0, 0};
		size_t status_len = status.length;
		ub8 ticket;
		size_t ticket_len = ticket.length;

		with (rapdu.apdu) sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_decode_card_data",
			"decode response(%i) %s", resplen, sc_dump_hex(resp, resplen));

		sc_copy_asn1_entry(c_asn1_acos5_64_sm_data_object.ptr, asn1_acos5_64_sm_data_object.ptr);
		sc_format_asn1_entry(asn1_acos5_64_sm_data_object.ptr + 0, resp_data.ptr, &resp_len,   0);
		sc_format_asn1_entry(asn1_acos5_64_sm_data_object.ptr + 1, status.ptr,    &status_len, 0);
		sc_format_asn1_entry(asn1_acos5_64_sm_data_object.ptr + 2, ticket.ptr,    &ticket_len, 0);

		if ((rv=sc_asn1_decode(ctx, asn1_acos5_64_sm_data_object.ptr, rapdu.apdu.resp, rapdu.apdu.resplen, null, null)) < 0) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_decode_card_data", "decode answer(s): ASN1 decode error");
			return rv;
		}

		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_decode_card_data",
			"decode response() SW:%02X%02X, MAC:%s", status[0], status[1], sc_dump_hex(ticket.ptr, ticket_len));
		if (status[0] != 0x90 || status[1] != 0x00)
			continue;

		if (asn1_acos5_64_sm_data_object[0].flags & SC_ASN1_PRESENT)   {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_decode_card_data", "decode answer() object present");
			if (resp_data[0] != 0x01) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_decode_card_data",
					"decode answer(s): invalid encrypted data format");
				return rv=SC_ERROR_INVALID_DATA;
			}

			if ((decrypted_len=decrypt_algo(resp_data[1..$], get_cwa_session_enc(*session_data).ptr, session_data.ssc.ptr, decrypted.ptr, cipher_TDES[CBC], false))%8 != 0) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_decode_card_data",
					"decode answer(s): cannot decrypt card answer data");
				return rv=SC_ERROR_DECRYPT_FAILED;
			}
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_decode_card_data",
				"decrypted data(%i) %s", decrypted_len, sc_dump_hex(decrypted.ptr, decrypted_len));
			while(*(decrypted.ptr + decrypted_len - 1) == 0x00)
				decrypted_len--;
			if   (*(decrypted.ptr + decrypted_len - 1) != 0x80) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_decode_card_data",
					"decode answer(s): invalid card data padding ");
				return rv=SC_ERROR_INVALID_DATA;
			}
			decrypted_len--;

			if (out_ && out_len)   {
				if (out_len < offs + decrypted_len) {
					sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_decode_card_data",
						"decode answer(s): insufficient output buffer size");
					return rv=SC_ERROR_BUFFER_TOO_SMALL;
				}

				memcpy(out_ + offs, decrypted.ptr, decrypted_len);

				offs += decrypted_len;
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_decode_card_data",
					"decode card answer(s): out_len/offs %i/%i", out_len, offs);
			}

//			free(decrypted);
		}
	} // for (rapdu = rdata.data; rapdu; rapdu = rapdu.next)

	return rv=offs;
}


private int sm_acos5_64_transmit_apdus(sc_card* card, sc_remote_data* rdata, ubyte* out_, size_t* out_len) {
	sc_context*     ctx   = card.ctx;
	sc_remote_apdu* rapdu = rdata.data;
	int             rv    = SC_SUCCESS, offs;// = 0;
	mixin (log!(q{"sm_acos5_64_transmit_apdus"}, q{"called"})); //
	mixin log_scope_exit!("sm_acos5_64_transmit_apdus"); 
	scope(exit)
		log_scope_exit_do();

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_transmit_apdus",
		"rdata-length %i", rdata.length);

	while (rapdu)   {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_transmit_apdus",
			"rAPDU flags 0x%X", rapdu.apdu.flags);
		if ((rv=sc_transmit_apdu(card, &rapdu.apdu)) < 0) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_transmit_apdus",
				"failed to execute r-APDU");
			return rv;
		}
		rv = sc_check_sw(card, rapdu.apdu.sw1, rapdu.apdu.sw2);
		if (rv < 0 && !(rapdu.flags & SC_REMOTE_APDU_FLAG_NOT_FATAL)) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_transmit_apdus",
				"fatal error");
			return rv;
		}

		if (out_ && out_len && (rapdu.flags & SC_REMOTE_APDU_FLAG_RETURN_ANSWER))   {
			size_t len = rapdu.apdu.resplen > (*out_len - offs) ? (*out_len - offs) : rapdu.apdu.resplen;

			memcpy(out_ + offs, rapdu.apdu.resp, len);
			offs += len;
			/* TODO: decode and gather data answers */
		}

		rapdu = rapdu.next;
	}

	if (out_len)
		*out_len = offs;

	return rv;
}


private extern(C) int sm_acos5_64_card_open(sc_card* card) {
/* used only once after init to test SM; will finally switch to mode acl */
	sc_context*      ctx = card.ctx;
	sc_remote_apdu*  rapdu;
	sc_remote_data   remote_data;
	sc_remote_data*  rdata = &remote_data;
	int rv = SC_SUCCESS;
	mixin (log!(q{"sm_acos5_64_card_open"}, q{"called"}));
	mixin alloc_rdata_rapdu!("sm_acos5_64_card_open");
	mixin log_scope_exit!("sm_acos5_64_card_open");
	scope(exit)
		log_scope_exit_do();

/**********************/
version(TRY_SM) {
	rv = SC_ERROR_UNKNOWN;

	const sc_path test_EF = sc_path(cast(immutable(ubyte)[SC_MAX_PATH_SIZE]) x"3F00 4100 3901 00000000000000000000", 6, 0, 0, SC_PATH_TYPE.SC_PATH_TYPE_PATH);
	if ((rv=acos5_64_select_file_by_path(card, &test_EF,  null)) != SC_SUCCESS)
		return rv=SC_ERROR_KEYPAD_CANCELLED;

	card.sm_ctx.info.serialnr = card.serialnr;

	if ((rv=acos5_64_get_challenge(card, card.sm_ctx.info.session.cwa.card_challenge.ptr, SM_SMALL_CHALLENGE_LEN)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open",
			"initialize: get_challenge failed\n");
		return rv;
	}

	sc_remote_data_init(rdata);

	if (!card.sm_ctx.module_.ops.initialize) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open", "No SM module");
		return rv=SC_ERROR_SM_NOT_INITIALIZED;
	}
	if ((rv=initialize(ctx, &card.sm_ctx.info, rdata)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open", "SM: INITIALIZE failed");
		return rv;
	}

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open",
		"external_authentication(): rdata length %i\n", rdata.length);

	size_t host_challenge_encrypted_tdesecb_with_key_card_done_by_card_len = 8;
	ub8    host_challenge_encrypted_tdesecb_with_key_card_done_by_card;
	ub8    host_challenge_encrypted_tdesecb_with_key_card_done_by_host; // both this and previous to be compared later

	if ((rv=sm_acos5_64_transmit_apdus (card, rdata, host_challenge_encrypted_tdesecb_with_key_card_done_by_card.ptr,
																									&host_challenge_encrypted_tdesecb_with_key_card_done_by_card_len)) < 0) {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open",
			"external_authentication(): execute failed");
		return rv;
	}
	rdata.free(rdata);

	with (card.sm_ctx.info.session)
		if (encrypt_algo(cwa.ifd.rnd, get_cwa_keyset_enc(cwa).ptr, null, host_challenge_encrypted_tdesecb_with_key_card_done_by_host.ptr,
				cipher_TDES[ECB], false) != host_challenge_encrypted_tdesecb_with_key_card_done_by_host.length)
			return rv=SC_ERROR_KEYPAD_TIMEOUT;

	if (!equal(host_challenge_encrypted_tdesecb_with_key_card_done_by_card[],
						 host_challenge_encrypted_tdesecb_with_key_card_done_by_host[])) {
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open",
		"        ### Card/Token and Host sym. keys configured are NOT suitable for Secure Messaging. The Mutual Authentication procedure failed ! ###");
		return rv=SC_ERROR_INTERNAL;
	}
	sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open",
		"        ### Card/Token and Host sym. keys configured are     suitable for Secure Messaging. The Mutual Authentication procedure succeeded ! ###");

version(TRY_SM_MORE) {
		/* session keys generation */
		with (card.sm_ctx.info.session) {
version(SESSIONKEYSIZE24)
			ub24  deriv_data = cwa.icc.rnd[4..8] ~ cwa.ifd.rnd[0..4] ~ cwa.icc.rnd[0..4] ~ cwa.ifd.rnd[4..8] ~ cwa.ifd.rnd[0..4] ~ cwa.icc.rnd[4..8];
else
			ub16  deriv_data = cwa.icc.rnd[4..8] ~ cwa.ifd.rnd[0..4] ~ cwa.icc.rnd[0..4] ~ cwa.ifd.rnd[4..8];

			ub24  enc_buf, mac_buf;
			if ((rv=encrypt_algo(deriv_data, get_cwa_keyset_enc(cwa).ptr, null/*iv*/, enc_buf.ptr, cipher_TDES[ECB], false)) != enc_buf.length)
				return rv=SC_ERROR_KEYPAD_TIMEOUT;
			if ((rv=encrypt_algo(deriv_data, get_cwa_keyset_mac(cwa).ptr, null/*iv*/, mac_buf.ptr, cipher_TDES[ECB], false)) != mac_buf.length)
				return rv=SC_ERROR_KEYPAD_TIMEOUT;
			set_cwa_session_enc(cwa, enc_buf);
			set_cwa_session_mac(cwa, mac_buf);
		}
/+
		   Testing usability of 	card.sm_ctx.info.session.cwa.session_enc in encryption
		writefln("deriv_data_encry_enc: 0x [ %(%x %) ]", get_cwa_session_enc(card.sm_ctx.info.session.cwa));
		writefln("deriv_data_encry_mac: 0x [ %(%x %) ]", get_cwa_session_mac(card.sm_ctx.info.session.cwa));
		writefln("deriv_data_plain:     0x [ %(%x %) ]", deriv_data);
		writeln;


		apdu = sc_apdu(); // SC_APDU_CASE_3_SHORT:       CLAINSP1  P2 lc
		bytes2apdu(card.ctx, cast(immutable(ubyte)[13])x"00 22 01  B8 08  80 01 02  95 01 C0  84 00", apdu);
		if ((rv=transmit_apdu_strerror_do)<0) return rv;
		if ((rv=sc_check_sw(card, apdu.sw1, apdu.sw2))<0) return rv;

		assert (plain_card.length%8==0);
		apdu = sc_apdu(); // SC_APDU_CASE_4_SHORT       CLAINSP1 P2 lc
version(SESSIONKEYSIZE24)
		bytes2apdu(card.ctx, cast(immutable(ubyte)[5])x"00 2A 84 80 18" ~ plain_card ~ cast(ubyte)24, apdu);
else
		bytes2apdu(card.ctx, cast(immutable(ubyte)[5])x"00 2A 84 80 10" ~ plain_card ~ cast(ubyte)16, apdu);
		apdu.resp    = cgram_response.ptr;
		apdu.resplen = cgram_response.length;
		if ((rv=transmit_apdu_strerror_do)<0) return rv;
		if ((rv=sc_check_sw(card, apdu.sw1, apdu.sw2))<0) return rv;

//		writefln("resp sw1, sw2 : %X, %X", apdu.sw1, apdu.sw2);
//		writefln("plain_card    : 0x [ %(%x %) ]", plain_card);
//		writefln("cgram_response: 0x [ %(%x %) ]", cgram_response);
//		with (card.sm_ctx.info.session.cwa)
		ub8  iv_zero;
		if ((rv=decrypt_algo(cgram_response, get_cwa_session_enc(card.sm_ctx.info.session.cwa).ptr, iv_zero.ptr/*ubyte* iv*/,
			plain_host.ptr, cipher_TDES[CBC], false ) ) != plain_host.length)
			return rv=SC_ERROR_KEYPAD_TIMEOUT;
//		writefln("plain_host    : 0x [ %(%x %) ]", plain_host);
//		writeln;
		if (!equal(plain_card, plain_host[]))
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open",
				"A trial enc/dec with session key failed\n");
		else
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open",
				"   ### A trial enc/dec with session key succeeded ###\n");
+/
//////////////
		/* Testing usability of 	card.sm_ctx.info.session.cwa.session_mac in an SM-Authenticity operation (erase all test file's contents (binary 3901, selected previously)
			 multiple calls to MSE  Set Security Environment accumulate the CRTs in system memory until they get erased by a select different DF/MF?
			 alternative: use MSE Restore of record #5, which exists, but currently requires Pin-Authentication on my token; mimic this now: */
		sc_remote_data_init(rdata);
		if ((rv=alloc_rdata_rapdu_do())<0) return rv;
		bytes2apdu(card.ctx, cast(immutable(ubyte)[3])x"00 22 01"~construct_sc_security_env(1, null, CCT, Session_Key_SM), rapdu.apdu);
		if ((rv=alloc_rdata_rapdu_do())<0) return rv;
		bytes2apdu(card.ctx, cast(immutable(ubyte)[3])x"00 22 01"~construct_sc_security_env(1, null, AT, SymKey_Authenticate, 0x82), rapdu.apdu); // requires the (already done) Authentication of key for External Auth.
		if ((rv=alloc_rdata_rapdu_do())<0) return rv;

		TSMarguments smArguments;
		with (card.sm_ctx.info.session)
			smArguments = TSMarguments(SC_APDU_CASE_3_SHORT, SM_CCT, [0x00, 0x0E, 0x00, 0x00], get_cwa_session_mac(cwa).ptr, cwa.ssc, 2, [0,5]);

		bytes2apdu(card.ctx, construct_SMcommand(smArguments[]) ~ ubyte(10)/*le*/, rapdu.apdu);
		rapdu.flags |= SC_REMOTE_APDU_FLAG_RETURN_ANSWER;
		rapdu.apdu.resp    = rapdu.rbuf.ptr;    // host_challenge_encrypted_tdesecb_with_key_card_done_by_card.ptr;
		rapdu.apdu.resplen = rapdu.rbuf.length; // host_challenge_encrypted_tdesecb_with_key_card_done_by_card.length;

		ub16    SM_response;
		size_t  SM_response_len;
		if ((rv=sm_acos5_64_transmit_apdus (card, rdata, SM_response.ptr, &SM_response_len)) < 0) {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open",
				"external_authentication(): execute failed");
			return rv;
		}
		rdata.free(rdata);

		if ((rv=sc_sm_update_apdu_response(card, rapdu.apdu.resp, rapdu.apdu.resplen, 0, &rapdu.apdu))<0) {
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open", "empty apdu.resp or sc_sm_parse_answer failed");
			return rv; // the response SW1SW2 got unwrapped and is now ready to be checked
		}
		if ((rv=sc_check_sw(card, rapdu.apdu.sw1, rapdu.apdu.sw2)) < 0) {
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open", "The SM command failed");
			return rv;
		}

		if ((rv=check_SMresponse(&rapdu.apdu, smArguments[0..$-2])) != SC_SUCCESS) {
			sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open", "    ### check_SMresponse failed! ###");
			return rv;
		}
		sc_do_log(card.ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_card_open",
			"        ##### SM Response Successfully Verified. Operation was performed as requested #####\n");

} // version(TRY_SM_MORE)
} // version(TRY_SM)
/**********************/

	with (card.sm_ctx) {
		sm_mode          = SM_MODE_ACL;
		ops.open         = null;
		ops.close        = null;
		ops.get_sm_apdu  = null;
		ops.free_sm_apdu = null;
	}
	return rv=SC_SUCCESS;
}


private extern(C) int sm_acos5_64_card_close(sc_card* card) {
	sc_context* ctx = card.ctx;
	int rv = SC_SUCCESS;
	mixin (log!(q{"sm_acos5_64_card_close"}, q{"called"})); //
	mixin log_scope_exit!("sm_acos5_64_card_close"); 
	scope(exit)
		log_scope_exit_do();
	return rv;
}

private extern(C) int sm_acos5_64_card_get_sm_apdu (sc_card* card, sc_apdu* apdu, sc_apdu** sm_apdu) {
	sc_context* ctx = card.ctx;
	int rv = SC_ERROR_SM_NOT_APPLIED;
	mixin (log!(q{"sm_acos5_64_card_get_sm_apdu"}, q{"called"})); //
	mixin log_scope_exit!("sm_acos5_64_card_get_sm_apdu"); 
	scope(exit)
		log_scope_exit_do();
	return rv;
}

private extern(C) int sm_acos5_64_card_free_sm_apdu(sc_card* card, sc_apdu* apdu, sc_apdu** sm_apdu) {
	return 0;
}

/**
 * missing export; code duplicate from smm-local.c
 */
private int sm_cwa_acos5_64_config_get_keyset(sc_context* ctx, sm_info* info)
{
	sm_cwa_session* cwa_session = &info.session.cwa;
	sm_cwa_keyset*  cwa_keyset  = &info.session.cwa.cwa_keyset;
	sc_crt*         cwa_crt_at  = &info.session.cwa.params.crt_at;
	scconf_block*   sm_conf_block;
	scconf_block**  blocks;
	const(char)*    value;
	char[128] name;
	ubyte[48] hex;
	size_t hex_len = hex.sizeof;
	int rv, ii, ref_ = cwa_crt_at.refs[0] & 0x1F /*IASECC_OBJECT_REF_MAX*/;

		mixin (log!(q{"sm_cwa_acos5_64_config_get_keyset"}, q{"called"})); //
		scope(exit) {
			if (rv <= 0)
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
					"returning with: %d (%s)\n", rv, sc_strerror(rv));
			else
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
					"returning with: %d\n", rv);
		}

	for (ii = 0; ctx.conf_blocks[ii]; ii++) {
		blocks = scconf_find_blocks(ctx.conf, ctx.conf_blocks[ii], "secure_messaging", info.config_section.ptr);
		if (blocks) {
			sm_conf_block = blocks[0];
			free(blocks);
		}

		if (sm_conf_block)
			break;
	}

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
		"CRT_AT(algo: 0x%02X, ref:0x%02X)", cwa_crt_at.algo, cwa_crt_at.refs[0]);
	/* Keyset ENC */
	if (info.current_aid.len && (cwa_crt_at.refs[0] & 0x80 /*IASECC_OBJECT_REF_LOCAL*/))
		snprintf(name.ptr, name.sizeof, "keyset_%s_%02i_enc",
				sc_dump_hex(info.current_aid.value.ptr, info.current_aid.len), ref_);
	else
		snprintf(name.ptr, name.sizeof, "keyset_%02i_enc", ref_);
	value = scconf_get_str(sm_conf_block, name.ptr, null);
	if (!value)   {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
			"No %s value in OpenSC config", name.ptr); // No keyset_00_enc value in OpenSC config
		return rv=SC_ERROR_SM_KEYSET_NOT_FOUND;
	}

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
		"keyset::enc(%i) %s", strlen(value), value);

version(SESSIONKEYSIZE24)
	immutable sessionkeyLen = 24;
else
	immutable sessionkeyLen = 16;

	{
		hex_len = hex.sizeof;
		if ((rv=sc_hex_to_bin(value, hex.ptr, &hex_len))!=0)   {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
				"SM get %s: hex to bin failed for '%s'; error %i", name.ptr, value, rv);
			return rv=SC_ERROR_UNKNOWN_DATA_RECEIVED;
		}

		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
			"ENC(%i) %s", hex_len, sc_dump_hex(hex.ptr, hex_len));
		if (hex_len != sessionkeyLen)
			return rv=SC_ERROR_INVALID_DATA;

		set_cwa_keyset_enc(info.session.cwa, hex);
	}

	/* Keyset MAC */
	if (info.current_aid.len && (cwa_crt_at.refs[0] & 0x80 /*IASECC_OBJECT_REF_LOCAL**/))
		snprintf(name.ptr, name.sizeof, "keyset_%s_%02i_mac",
				sc_dump_hex(info.current_aid.value.ptr, info.current_aid.len), ref_);
	else
		snprintf(name.ptr, name.sizeof, "keyset_%02i_mac", ref_);
	value = scconf_get_str(sm_conf_block, name.ptr, null);
	if (!value)   {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
			"No %s value in OpenSC config", name.ptr);
		return rv=SC_ERROR_SM_KEYSET_NOT_FOUND;
	}

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
		"keyset::mac(%i) %s", strlen(value), value);
	{
		hex_len = hex.sizeof;
		if ((rv=sc_hex_to_bin(value, hex.ptr, &hex_len))!=0)   {
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
				"SM get '%s': hex to bin failed for '%s'; error %i", name.ptr, value, rv);
			return rv=SC_ERROR_UNKNOWN_DATA_RECEIVED;
		}

		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
			"MAC(%i) %s", hex_len, sc_dump_hex(hex.ptr, hex_len));
		if (hex_len != sessionkeyLen)
			return rv=SC_ERROR_INVALID_DATA;

		set_cwa_keyset_mac(info.session.cwa, hex);
	}

	cwa_keyset.sdo_reference = cwa_crt_at.refs[0];


	/* IFD parameters */
	value = scconf_get_str(sm_conf_block, "ifd_serial", null);
	if (!value)
		return rv=SC_ERROR_SM_IFD_DATA_MISSING;
	hex_len = hex.sizeof;
	if ((rv=sc_hex_to_bin(value, hex.ptr, &hex_len))!=0)   {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
			"SM get 'ifd_serial': hex to bin failed for '%s'; error %i", value, rv);
		return rv=SC_ERROR_UNKNOWN_DATA_RECEIVED;
	}

	if (hex_len != cwa_session.ifd.sn.sizeof)   {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
			"SM get 'ifd_serial': invalid IFD serial length: %i", hex_len);
		return rv=SC_ERROR_UNKNOWN_DATA_RECEIVED;
	}

	memcpy(cwa_session.ifd.sn.ptr, hex.ptr, hex_len);
	if (!equal(cwa_session.ifd.sn[], representation("acos5_64")) && !equal(cwa_session.ifd.sn[], cwa_session.icc.sn[]))
		return rv=SC_ERROR_NO_READERS_FOUND;
	if ((rv=RAND_bytes(cwa_session.ifd.rnd.ptr, cwa_session.ifd.rnd.length))==0)   {
		sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
			"Generate random error: %i", rv);
		return rv=SC_ERROR_SM_RAND_FAILED;
	}

	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
		"IFD.Serial: %s", sc_dump_hex(cwa_session.ifd.sn.ptr, cwa_session.ifd.sn.sizeof));
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
		"IFD.Rnd: %s", sc_dump_hex(cwa_session.ifd.rnd.ptr, cwa_session.ifd.rnd.sizeof));
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_config_get_keyset",
		"IFD.K: %s", sc_dump_hex(cwa_session.ifd.k.ptr, cwa_session.ifd.k.sizeof));

	return rv=SC_SUCCESS;
}


int sm_cwa_acos5_64_initialize(sc_context* ctx, sm_info* info, sc_remote_data* rdata) {
	int              rv;
	sc_remote_apdu*  rapdu;
	mixin (log!(q{"sm_cwa_acos5_64_initialize"}, q{"called"}));
	mixin alloc_rdata_rapdu!("sm_cwa_acos5_64_initialize");
	mixin log_scope_exit!("sm_cwa_acos5_64_initialize"); 
	scope(exit)
		log_scope_exit_do();
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_initialize",
		"initialize: serial %s", sc_dump_hex(info.serialnr.value.ptr, info.serialnr.len));
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_initialize",
		"initialize: card challenge %s", sc_dump_hex(info.session.cwa.card_challenge.ptr, 8));
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_initialize",
		"initialize: current_df_path %s", sc_print_path(&info.current_path_df));
	sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_cwa_acos5_64_initialize",
		"initialize: CRT_AT reference 0x%X", info.session.cwa.params.crt_at.refs[0]);

	if (!rdata || !rdata.alloc)
		return rv=SC_ERROR_INVALID_ARGUMENTS;

	ub8  card_challenge_encrypted_tdesecb_with_key_host_done_by_host;

	with (info.session)
		if ((rv=encrypt_algo(cwa.icc.rnd, get_cwa_keyset_mac(cwa).ptr, null, card_challenge_encrypted_tdesecb_with_key_host_done_by_host.ptr,
				cipher_TDES[ECB], false)) != card_challenge_encrypted_tdesecb_with_key_host_done_by_host.length)
			return rv=SC_ERROR_KEYPAD_TIMEOUT;

	if ((rv=alloc_rdata_rapdu_do())<0) return rv;
	// SC_APDU_CASE_3_SHORT,le=0               CLAINSP1 P2 lc    Ext. Auth.; if this succeeds, key_host/get_cwa_keyset_mac(card.sm_ctx.info.session.cwa) is authenticated from card's point of view
	bytes2apdu(ctx, cast(immutable(ubyte)[5])x"00 82 00 82 08" ~ card_challenge_encrypted_tdesecb_with_key_host_done_by_host, rapdu.apdu);

	if ((rv=alloc_rdata_rapdu_do())<0) return rv;
	// SC_APDU_CASE_4_SHORT,le=8               CLAINSP1 P2 lc   Int. Auth.; this doesn't authenticate key_card/get_cwa_keyset_enc(card.sm_ctx.info.session.cwa) seen from card's point of view
	bytes2apdu(ctx, cast(immutable(ubyte)[5])x"00 88 00 81 08" ~ info.session.cwa.ifd.rnd ~ ubyte(8)/*le*/, rapdu.apdu);
	rapdu.flags |= SC_REMOTE_APDU_FLAG_RETURN_ANSWER;
	rapdu.apdu.resp    = rapdu.rbuf.ptr;    // host_challenge_encrypted_tdesecb_with_key_card_done_by_card.ptr;
	rapdu.apdu.resplen = rapdu.rbuf.length; // host_challenge_encrypted_tdesecb_with_key_card_done_by_card.length;

	return rv=SC_SUCCESS;
}


/** API of the external SM module */
/**
 * Initialize
 *
 * Read keyset from the OpenSC configuration file,
 * get and return the APDU(s) to initialize SM session.
 */
export extern(C) int /*sm_acos5_64_*/ initialize(sc_context* ctx, sm_info* info, sc_remote_data* rdata)
{
	int rv = SC_ERROR_NOT_SUPPORTED;
	mixin (log!(q{"sm_acos5_64_initialize"}, q{"called"}));
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_initialize",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_initialize",
				"returning with: %d\n", rv);
	}

	if (!info)
		return rv=SC_ERROR_INVALID_ARGUMENTS;

	with (info.current_aid) sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_initialize",
		"Current AID: %s", sc_dump_hex(value.ptr, len));
	final switch (cast(SM_TYPE)info.sm_type) {
		case SM_TYPE_CWA14890:
			if ((rv=sm_cwa_acos5_64_config_get_keyset(ctx, info)) < 0) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_initialize",
				"SM acos5_64 configuration error: %d (%s)\n", rv, sc_strerror(rv));
				return rv;
			}

			if ((rv=sm_cwa_acos5_64_initialize(ctx, info, rdata)) < 0) {
				sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_initialize",
					"SM acos5_64 initializing error: %d (%s)\n", rv, sc_strerror(rv));
				return rv;
			}
			break;
		case SM_TYPE_GP_SCP01, SM_TYPE_DH_RSA:
			rv = SC_ERROR_NOT_SUPPORTED;
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_initialize",
				"unsupported SM type: %d (%s)\n", rv, sc_strerror(rv));
			return rv;
	}

	return rv=SC_SUCCESS;
}


/**
 * Get APDU(s)
 *
 * Get securized APDU(s) corresponding
 * to the asked command.
 */
export extern(C) int /*sm_acos5_64_*/ get_apdus(sc_context* ctx, sm_info* info, ubyte* init_data, size_t init_len, sc_remote_data* rdata)
{
	int rv = SC_ERROR_NOT_SUPPORTED;
	mixin (log!(q{"sm_acos5_64_initialize"}, q{"called"}));
	scope(exit) {
		if (rv <= 0)
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_initialize",
				"returning with: %d (%s)\n", rv, sc_strerror(rv));
		else
			sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, __MODULE__, __LINE__, "sm_acos5_64_initialize",
				"returning with: %d\n", rv);
	}
	return rv;
}