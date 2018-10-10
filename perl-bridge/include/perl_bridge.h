#ifndef PERL_BRIDGE_H_
#define PERL_BRIDGE_H_

#include <string.h>

#ifdef __cplusplus
extern "C"{
#endif

typedef struct perl_bridge_ perl_bridge_t;

void perl_bridge_initialize(int argc, char *argv[]);

void perl_bridge_terminate();

perl_bridge_t *perl_bridge_create(const char *include_path, const char *file_path);

const char *perl_bridge_cache_key(const char *data, size_t length);

void perl_bridge_release(perl_bridge_t *object);

#ifdef __cplusplus
}
#endif

#endif
