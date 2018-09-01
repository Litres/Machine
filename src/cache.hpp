#pragma once

#include <string>
#include <memory>
#include <exception>

#include <json.hpp>
#include <libmemcached/memcached.h>

#include <boost/optional.hpp>

#include "log.hpp"

namespace machine
{
namespace cache
{

using json = nlohmann::json;

class Cache
{
public:
	virtual void set(const std::string& key, const json& object) = 0;

	virtual boost::optional<json> get(const std::string& key) = 0;

	virtual ~Cache() = default;

protected:
	Cache() = default;
};

class NullCache : public Cache
{
public:
	void set(const std::string& key, const json& object) override
	{
	}

	boost::optional<json> get(const std::string& key) override
	{
		return boost::none;
	}
};

class DefaultCache : public Cache
{
public:
	explicit DefaultCache(const json &settings) : handle_(nullptr)
	{
		const json &parameters = settings["cache"];
		const std::string &configuration = parameters["configuration"];
		handle_ = memcached(configuration.c_str(), configuration.size());
		if (handle_ == nullptr)
		{
			std::runtime_error("default cache");
		}
	}

	~DefaultCache() override
	{
		if (handle_ != nullptr)
		{
			memcached_free(handle_);
		}
	}

	void set(const std::string& key, const json& object) override
	{
		std::vector<uint8_t> value = json::to_msgpack(object);
		auto data = (const char *)value.data();

		time_t expiration = 0;
		uint32_t flags = 0;

		memcached_return_t result = memcached_set(handle_, key.c_str(), key.size(),
			data, value.size(), expiration, flags);

		if (result != MEMCACHED_SUCCESS)
		{
			logger::get()->error("fail to set key {0} to cache with error {1}", key, result);
		}
	}

	boost::optional<json> get(const std::string& key) override
	{
		size_t size = 0;
		uint32_t flags = 0;
		memcached_return_t error = MEMCACHED_SUCCESS;

		char *value = memcached_get(handle_, key.c_str(), key.size(), &size, &flags, &error);
		if (value != nullptr)
		{
			return json::from_msgpack(std::vector<uint8_t>(value, value + size));
		}
		else
		{
			logger::get()->error("fail to get key {0} from cache with error {1}", key, error);
			return boost::none;
		}
	}

private:
	memcached_st *handle_;
};

}
}
