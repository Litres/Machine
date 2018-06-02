#pragma once

#include <memory>
#include <fstream>

#include <json.hpp>

#include "sql.hpp"
#include "cache.hpp"

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

		database_ = std::make_shared<sql::Database<Context>>();

		if (settings_.find("cache") != settings_.end())
		{
			cache_.reset(new cache::DefaultCache(settings_));
		}
		else
		{
			cache_.reset(new cache::NullCache());
		}

	}

	const nlohmann::json &settings() const
	{
		return settings_;
	}

	std::shared_ptr<sql::Database<Context>> database()
	{
		return database_;
	}

	cache::Cache *cache()
	{
		return cache_.get();
	}

private:
	Context() = default;

	nlohmann::json settings_;
	std::shared_ptr<sql::Database<Context>> database_;
	std::unique_ptr<cache::Cache> cache_;
};

}
