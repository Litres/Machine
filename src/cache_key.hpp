#pragma once

#include <set>

#include <boost/algorithm/string/join.hpp>

#include <json.hpp>

#include "log.hpp"
#include "hash.hpp"
#include "common.hpp"

namespace machine
{
namespace cache
{

using json = nlohmann::json;

std::string body_cache_key(const json &object, const json &data, const std::string &r_cache_key)
{
	const json &body = object["body"];
	auto p1 = body.find("cache_key");
	if (p1 != body.end())
	{
		return *p1;
	}

	std::vector<std::string> list;

	const json &data_request = data["request"];
	auto p2 = data_request.find("cache_key_prefix");
	if (p2 != data_request.end())
	{
		list.push_back(*p2);
	}

	json parameters = body["params"];

	// resolve parameters
	Resolver r(json::object({ {"data", data} }));
	for (json::iterator j = parameters.begin(); j != parameters.end(); j++)
	{
		if (j.value().is_string())
		{
			j.value() = r.resolve(j.value());
		}
	}

	list.push_back(body["request"]);
	list.push_back(parameters.dump());

	std::string parent_key;
	list.push_back(parent_key);

	const json &sql = parameters["sql"];
	const std::string alias = *sql.begin();

	std::set<std::string> s = {"dbh", "dbhr", "dbstat", "ddos"};
	if (s.find(alias) == s.end())
	{
		auto p3 = data_request["Lib"].get<long>();
		list.push_back(std::to_string(p3));
	}

	if (!r_cache_key.empty())
	{
		list.push_back(r_cache_key);
	}

	HashBuilder hash;
	hash.update(boost::algorithm::join(list, "::"));

	return "body:" + hash.final();
}

}
}
