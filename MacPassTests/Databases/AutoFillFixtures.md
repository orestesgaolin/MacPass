AutoFill database fixtures copied from KeePassKit at the revision vendored in
`Carthage/Checkouts/KeePassKit`. They retain the upstream test credentials and
are used only by `MacPassTests`.

- `AutoFill_KDB_KeyFile.kdb`: `No_Password_Kdb1HexKey_Keyfile.kdb`
- `AutoFill_KDB_Combined.kdb`: `KDB1_Password_1234_Keyfile_Kdb1HexKey.kdb`
- `AutoFill_KDBX31_KeyFile.kdbx`: `No_Password_Kdb1HexKey_Keyfile.kdbx`
- `AutoFill_KDBX4_Password.kdbx`: `Argon2KDF_AES_Cipher_test.kdbx`
- `AutoFill_KDBX4_Combined.kdbx`: `Database_test_keyFileV2.kdbx`
- `AutoFill_KDBX41_Password.kdbx`: `Kdbx4.1/Database_test.kdbx`
- `AutoFill_Kdb1HexKey.key`: `Keyfiles/Kdb1HexKey.key`
- `AutoFill_KeyFileV2.keyx`: `Kdbx4/Database_test_keyFileV2.keyx`

Upstream passwords are `test` for the KDB combined fixture and the KDBX 4 and
4.1 fixtures. `Test_Password_1234.kdb` and `Test_Password_1234.kdbx`, already
in the test bundle, use `1234`.
