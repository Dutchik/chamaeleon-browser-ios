#ifndef CHM_RULES_H
#define CHM_RULES_H

// Chamaeleon ネットワーク判定エンジン（C）。
// メインフレームのナビゲーションを Swift から評価してブロック可否を返す。
// action: 0 = allow, 1 = block

#ifdef __cplusplus
extern "C" {
#endif

void chm_rules_clear(void);
void chm_rules_add(const char *pattern, int action);   // pattern の部分一致（大小無視）
int  chm_rules_eval(const char *url);                  // 最初に一致したルールの action、無ければ 0
int  chm_rules_count(void);

#ifdef __cplusplus
}
#endif

#endif /* CHM_RULES_H */
