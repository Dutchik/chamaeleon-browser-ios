#include "chm_mitm.h"
// iOS版: OpenSSL非搭載のためMITMは無効（HTTPSはブラインドトンネル）。
// 平文HTTPのキャプチャ/書換のみ動作する。将来 iOS用OpenSSL(xcframework)導入で有効化予定。
int  chm_mitm_init(const char *ca_dir) { (void)ca_dir; return -1; }
const char *chm_mitm_ca_cert_der_path(void) { return 0; }
int  chm_mitm_bridge(int client_fd, const char *host, int origin_fd) { (void)client_fd; (void)host; (void)origin_fd; return -1; }
