#include "perl_bridge.h"

#include <EXTERN.h>
#include <perl.h>

EXTERN_C void xs_init(pTHX);

struct perl_bridge_ {
    PerlInterpreter *interpreter;
};

void perl_bridge_initialize(int argc, char *argv[])
{
    char **env = NULL;
    PERL_SYS_INIT3(&argc, &argv, &env);
}

void perl_bridge_terminate()
{
    PERL_SYS_TERM();
}

perl_bridge_t *perl_bridge_create(const char *include_path, const char *file_path) {
    perl_bridge_t *result = malloc(sizeof(perl_bridge_t));

    result->interpreter = perl_alloc();
    perl_construct(result->interpreter);

    char *embedding[] = { "", "-I", include_path, file_path };
    perl_parse(result->interpreter, xs_init, 4, embedding, (char **)NULL);

    perl_run(result->interpreter);

    return result;
}

const char *perl_bridge_cache_key(const char *data, size_t length)
{
    dTHX;

    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSVpv(data, length)));
    PUTBACK;

    call_pv("cache_key", G_SCALAR);
    SPAGAIN;

    STRLEN result_length;
    const char *result = SvPVx(POPs, result_length);

    char *string = malloc(result_length + 1);
    string[result_length] = 0;
    memcpy(string, result, result_length);

    PUTBACK;

    FREETMPS;
    LEAVE;

    return string;
}


void perl_bridge_release(perl_bridge_t *object)
{
    if (object->interpreter != NULL)
    {
        perl_destruct(object->interpreter);
        perl_free(object->interpreter);
    }

    free(object);
}
