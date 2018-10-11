#pragma once

#include <memory>
#include <fstream>

#include <json.hpp>

#include "db.hpp"
#include "cache.hpp"
#include "perl.hpp"

namespace machine
{

class Context
{
public:
    static Context &instance()
    {
        static Context context;
        return context;
    }

    void setup()
    {
        std::ifstream file("settings.json");
        file >> settings_;

        database_ = std::make_unique<machine::sql::DefaultDatabase>(settings_);

        if (settings_.find("cache") != settings_.end())
        {
            cache_ = std::make_unique<cache::DefaultCache>(settings_);
        }
        else
        {
            cache_ = std::make_unique<cache::NullCache>();
        }

        perl_ = std::make_unique<perl::PerlService>(settings_);
    }

    const nlohmann::json &settings() const
    {
        return settings_;
    }

    machine::sql::Database &database()
    {
        return *database_;
    }

    cache::Cache &cache()
    {
        return *cache_;
    }

    perl::PerlServiceType &perl()
    {
        return *perl_;
    }

private:
    Context() = default;

    nlohmann::json settings_;

    std::unique_ptr<machine::sql::Database> database_;
    std::unique_ptr<cache::Cache> cache_;
    std::unique_ptr<perl::PerlServiceType> perl_;
};

}
