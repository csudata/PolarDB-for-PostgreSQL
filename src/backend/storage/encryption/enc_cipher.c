/*-------------------------------------------------------------------------
 *
 * enc_cipher.c
 *	  This code handles encryption and decryption using OpenSSL
 *
 * Portions Copyright (c) 2019, PostgreSQL Global Development Group
 * Portions Copyright (c) 2020, Alibaba Group Holding Limited
 *
 *
 * IDENTIFICATION
 *	  src/backend/storage/encryption/enc_cipher.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "storage/enc_cipher.h"
#include "storage/enc_common.h"
#include "storage/enc_internal.h"

/* GUC parameter */
int data_encryption_cipher;
int	EncryptionKeySize;
bool    polar_enable_tde_warning = true;

/* Data encryption */
void
pg_tde_encrypt(const char *input, char *output, int size,
		   const char *key, const char *iv)
{
#ifdef USE_OPENSSL
	ossl_encrypt_data(input, output, size, key, iv);
#else
	ereport(ERROR,
			(errcode(ERRCODE_CONFIG_FILE_ERROR),
			 (errmsg("cluster encryption is not supported because OpenSSL is not supported by this build"),
			  errhint("Compile with --with-openssl to use cluster encryption."))));
#endif
}

/* Data decryption */
void
pg_decrypt(const char *input, char *output, int size,
		   const char *key, const char *iv)
{
#ifdef USE_OPENSSL
	ossl_decrypt_data(input, output, size, key, iv);
#else
	ereport(ERROR,
			(errcode(ERRCODE_CONFIG_FILE_ERROR),
			 (errmsg("cluster encryption is not supported because OpenSSL is not supported by this build"),
			  errhint("Compile with --with-openssl to use cluster encryption."))));
#endif
}

/* HMAC computation */
void
pg_compute_hmac(const unsigned char *hmac_key, int key_size, unsigned char *data,
				int data_size,	unsigned char *hmac)
{
#ifdef USE_OPENSSL
	ossl_compute_hmac(hmac_key, key_size, data, data_size, hmac);
#else
	ereport(ERROR,
			(errcode(ERRCODE_CONFIG_FILE_ERROR),
			 (errmsg("cluster encryption is not supported because OpenSSL is not supported by this build"),
			  errhint("Compile with --with-openssl to use cluster encryption."))));
#endif
}

/* Key wrap */
void
pg_wrap_key(const unsigned char *key, int key_size, unsigned char *in,
			int in_size, unsigned char *out, int *out_size)
{
#ifdef USE_OPENSSL
	ossl_wrap_key(key, key_size, in, in_size, out, out_size);
#else
	ereport(ERROR,
			(errcode(ERRCODE_CONFIG_FILE_ERROR),
			 (errmsg("cluster encryption is not supported because OpenSSL is not supported by this build"),
			  errhint("Compile with --with-openssl to use cluster encryption."))));
#endif
}

/* Key unwrap */
void
pg_unwrap_key(const unsigned char *key, int key_size, unsigned char *in,
			  int in_size, unsigned char *out, int *out_size)
{
#ifdef USE_OPENSSL
	ossl_unwrap_key(key, key_size, in, in_size, out, out_size);
#else
	ereport(ERROR,
			(errcode(ERRCODE_CONFIG_FILE_ERROR),
			 (errmsg("cluster encryption is not supported because OpenSSL is not supported by this build"),
			  errhint("Compile with --with-openssl to use cluster encryption."))));
#endif
}

/* Convert cipher name string to integer value */
int
EncryptionCipherValue(const char *name)
{
	if (strcmp(name, "aes-128") == 0)
		return TDE_ENCRYPTION_AES_128;
	else if (strcmp(name, "aes-256") == 0)
		return TDE_ENCRYPTION_AES_256;
#if OPENSSL_VERSION_NUMBER >= 0x10101000L
#ifndef OPENSSL_NO_SM4
	else if(strcmp(name, "sm4") == 0)
		return TDE_ENCRYPTION_SM4;
#endif
#endif
	else
		/*no cover line*/
		return TDE_ENCRYPTION_OFF;
}

/* Convert integer value to cipher name string */
char *
EncryptionCipherString(int value)
{
	switch (value)
	{
		case TDE_ENCRYPTION_OFF :
			return "off";
		case TDE_ENCRYPTION_AES_128:
			return "aes-128";
		case TDE_ENCRYPTION_AES_256:
			return "aes-256";
#if OPENSSL_VERSION_NUMBER >= 0x10101000L
#ifndef OPENSSL_NO_SM4
		case TDE_ENCRYPTION_SM4:
			return "sm4";
#endif
#endif
		/*no cover begin*/
		default:
			elog(ERROR, "the encryption_cipher is not in the data_encryption_cipher_options!");
			return "unknown";
		/*no cover end*/
	}
}

void
assign_data_encryption_cipher(int new_encryption_cipher, void *extra)
{
	switch (new_encryption_cipher)
	{
		case TDE_ENCRYPTION_OFF:
			EncryptionKeySize = 0;
			break;
		case TDE_ENCRYPTION_AES_128:
#if OPENSSL_VERSION_NUMBER >= 0x10101000L
#ifndef OPENSSL_NO_SM4
		case TDE_ENCRYPTION_SM4:
#endif
#endif
			EncryptionKeySize = 16;
			break;
		case TDE_ENCRYPTION_AES_256:
			EncryptionKeySize = 32;
			break;
		/*no cover begin*/
		default:
			elog(ERROR, "the encryption_cipher is not in the data_encryption_cipher_options!");
			break;
		/*no cover end*/
	}
}
