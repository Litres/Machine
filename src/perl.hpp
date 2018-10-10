#pragma once

#include <memory>
#include <mutex>
#include <thread>
#include <unordered_map>

#include <json.hpp>

#include "log.hpp"
#include "perl_bridge.h"

namespace machine
{
namespace perl
{
    using json = nlohmann::json;

    struct Setup
    {
        Setup(int argc, char *argv[])
        {
            perl_bridge_initialize(argc, argv);
        }

        ~Setup()
        {
            perl_bridge_terminate();
        }
    };

    class PerlServiceType
    {
    public:
        virtual std::string cache_key(const json &object) = 0;

    protected:
        PerlServiceType() = default;
    };

    class PerlService : public PerlServiceType
    {
    public:
        explicit PerlService(const json &settings)
        {
            const json &parameters = settings["perl"];
            include_ = parameters["include"];
            file_ = parameters["file"];
        }

        std::string cache_key(const json &object) override
        {
            std::lock_guard<std::mutex> guard(mutex_);

            auto key = std::this_thread::get_id();
            if (pool_.find(key) == pool_.end())
            {
                pool_[key] = perl_bridge_create(include_.c_str(), file_.c_str());
            }

            std::string s = object.dump();
            auto result = std::string(perl_bridge_cache_key(s.c_str(), s.size()));

            logger::get()->debug("Perl bridge cache key value {0}", result);

            return result;
        }

        ~PerlService()
        {
            for (auto e : pool_)
            {
                perl_bridge_release(e.second);
            }
        }

    private:
        typedef std::unordered_map<std::thread::id, perl_bridge_t *> Pool;

        std::string include_;
        std::string file_;

        std::mutex mutex_;
        Pool pool_;
    };
}
}
