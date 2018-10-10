#pragma once

#include <boost/algorithm/string/join.hpp>

#include <json.hpp>

#include "common.hpp"
#include "function.hpp"
#include "db.hpp"
#include "cache.hpp"
#include "cache_key.hpp"

namespace machine
{
namespace sql
{

using json = nlohmann::json;

template <typename Context>
struct ParentSQLFunction : public Function
{
	ParentSQLFunction(size_t level, bool use_cache, const json &object, Queue &results) 
		: Function(level, use_cache, object, results) {}

	json execute(const json &v) const override
	{
		json list = json::object();
		std::string body_key;

		if (use_cache_)
		{
			body_key = create_body_key(v);
			if (boost::optional<json> value = Context::instance().cache().get(body_key))
			{
				logger::get()->debug("entry found for body key {0}", body_key);

				list = (*value)["data"]["list"];
			}
		}

		if (list.empty())
		{
			Query query(object_, v);

			json hash = json::object();
			json order = json::array();

			for (json &row : Context::instance().database().execute(query))
			{
				auto p = row.find("id");
				if (p == row.end())
				{
					throw std::logic_error("id not found");
				}
				std::string key = std::to_string(p->get<long>());
				hash[key] = row;
				order.push_back({ {"id", key} });
			}

			list["hash_by_id"] = hash;
			list["rows"] = hash.size();
			list["ordered_list"] = order;

			json data = json::object();
			data["list"] = list;

			if (!body_key.empty())
			{
				Context::instance().cache().set(body_key, json::object({ {"data", data} }));
			}
		}

		list["parent"] = true;
		list["path"] = object_["body"]["params"]["list_path"];

		json result = json::object();
		result["list"] = list;

		results_.push(Result(level_, json::object({ {"result", result} })));

		json data(v);
		data["result"] = result;

		return data;
	}

private:
	std::string create_body_key(const json &v) const
	{
		json cache_key_input(object_);
		cache_key_input["data"] = v;

		std::string r_cache_key = Context::instance().perl().cache_key(cache_key_input);
		return cache::body_cache_key(object_, v, r_cache_key);
	}
};

std::set<std::string> extract_keys(const json &data)
{
	const json &hash = data["result"]["list"]["hash_by_id"];

	std::set<std::string> result;
	for (json::const_iterator i = hash.begin(); i != hash.end(); i++)
	{
		result.insert(i.key());
	}

	return result;
}

template <typename Context>
struct ChildSQLFunction : public Function
{
	ChildSQLFunction(size_t level, bool use_cache, const json &object, Queue &results) 
		: Function(level, use_cache, object, results) {}

	json execute(const json &v) const override
	{
		json hash = json::object();

		std::set<std::string> missed_keys;
		std::string body_key;	

		if (use_cache_)
		{
			body_key = create_body_key(v);

			auto row_keys = extract_keys(v);
			for (auto &key : row_keys)
			{
				auto total_key = body_key + "::" + key;
				if (boost::optional<json> value = Context::instance().cache().get(total_key))
				{
					logger::get()->debug("entry found for key {0}", total_key);
					hash[key] = (*value)["data"];
				}
				else
				{
					missed_keys.insert(key);
				}
			}
		}
		else
		{
			missed_keys = extract_keys(v);
		}

		if (!missed_keys.empty())
		{
			Query query(object_, v);
			query.place(":ids", boost::algorithm::join(missed_keys, ","));

			json rows = json::object();
			for (json &row : Context::instance().database().execute(query))
			{
				auto p1 = row.find("id");
				if (p1 == row.end())
				{
					throw std::logic_error("id not found");
				}

				std::string key = std::to_string(p1->get<long>());
				// check unexpected key
				if (missed_keys.find(key) == missed_keys.end())
				{
					logger::get()->warn("unexpected key {0}", key);
					continue;
				}

				if (rows.find(key) == rows.end())
				{
					rows[key] = json::array();
				}

				// process id
				auto p2 = row.find("as_id");
				if (p2 != row.end())
				{
					*p1 = *p2;
					row.erase(p2);
				}
				else
				{
					row.erase(p1);
				}

				rows[key].push_back(row);
			}

			for (json::iterator i = rows.begin(); i != rows.end(); i++)
			{
				json row = json::object();

				const auto& parameters = object_["body"]["params"];
				const auto p1 = parameters.find("hash_of_lists");
				if (p1 != parameters.end())
				{
					const json &path = *p1;
					
					json::pointer p2 = &row;
					for (size_t j = 0; j < path.size() - 1; j++)
					{
						json &current = *p2;
						std::string key = path[j];
						current[key] = json::object();
						p2 = &(current[key]);
					}
					json &current = *p2;
					current[path.back().get<std::string>()] = i.value();
				}
				else
				{
					json &array = i.value();
					if (array.size() == 1)
					{
						json &e = array[0];
						for (json::iterator j = e.begin(); j != e.end(); j++)
						{
							row[j.key()] = j.value();
						}
					}
				}

				hash[i.key()] = row;
			}

			if (!body_key.empty())
			{
				for (auto &key : missed_keys)
				{
					// we need to have rows for all keys
					if (hash.find(key) == hash.end())
					{
						hash[key] = json::object();
					}

					auto total_key = body_key + "::" + key;
					Context::instance().cache().set(total_key, json::object({ {"data", hash[key]}, {"id", key} }));
				}
			}
		}

		json list = json::object();

		list["hash_by_id"] = hash;
		list["rows"] = hash.size();

		json result = json::object();
		result["list"] = list;

		results_.push(Result(level_, json::object({ {"result", result} })));

		json data(v);
		merge(result, data["result"]);

		return data;
	}

private:
	std::string create_body_key(const json &v) const
	{
		json cache_key_input(object_);
		cache_key_input["data"] = v;

		std::string r_cache_key = Context::instance().perl().cache_key(cache_key_input);
		return cache::body_cache_key(object_, v, r_cache_key);
	}	
};

}
}
