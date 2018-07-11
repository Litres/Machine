#pragma once

#include <json.hpp>

#include "common.hpp"
#include "function.hpp"
#include "db.hpp"

namespace machine
{
namespace sql
{

using json = nlohmann::json;

template <typename Context>
struct ParentSQLFunction : public Function
{
	ParentSQLFunction(const json &object, Queue &results) : Function(object, results) {}

	json execute(const json &v) const override
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

		json list = json::object();
		list["parent"] = true;
		list["hash_by_id"] = hash;
		list["rows"] = hash.size();
		list["ordered_list"] = order;
		list["path"] = object_["body"]["params"]["list_path"];

		json result = json::object();
		result["list"] = list;

		results_.push(Result(json::object({ {"result", result} })));

		json data(v);
		data["result"] = result;

		return data;
	}
};

std::string extract_keys(const json &data)
{
	const json &hash = data["result"]["list"]["hash_by_id"];

	std::string result;
	size_t counter = 0;
	for (json::const_iterator i = hash.begin(); i != hash.end(); i++)
	{
		result += i.key();
		if (counter++ != hash.size() - 1)
		{
			result += ",";
		}
	}

	return result;
}

template <typename Context>
struct ChildSQLFunction : public Function
{
	ChildSQLFunction(const json &object, Queue &results) : Function(object, results) {}

	json execute(const json &v) const override
	{
		Query query(object_, v);

		json data(v);
		query.place(":ids", extract_keys(data));

		json rows = json::object();
		for (json &row : Context::instance().database().execute(query))
		{
			auto p1 = row.find("id");
			if (p1 == row.end())
			{
				throw std::logic_error("id not found");
			}

			std::string key = std::to_string(p1->get<long>());
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

		json hash = json::object();

		for (json::iterator i = rows.begin(); i != rows.end(); i++)
		{
			json row = json::object();

			json &array = i.value();
			if (array.size() == 1)
			{
				json &e = array[0];
				for (json::iterator j = e.begin(); j != e.end(); j++)
				{
				    row[j.key()] = j.value();
				}
			}
			else
			{
				json::pointer p = &row;
				const json &path = object_["body"]["params"]["hash_of_lists"];
				for (size_t j = 0; j < path.size() - 1; j++)
				{
					json &current = *p;
					std::string key = path[j];
					current[key] = json::object();
					p = &(current[key]);
				}
				json &current = *p;
				current[path.back().get<std::string>()] = array;
			}

			hash[i.key()] = row;
		}

		json list = json::object();
		list["hash_by_id"] = hash;
		list["rows"] = hash.size();

		json result = json::object();
		result["list"] = list;

		results_.push(Result(json::object({ {"result", result} })));

		merge(result, data["result"]);

		return data;
	}
};

}
}
