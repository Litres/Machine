#pragma once

#include <memory>
#include <sstream>

#include <spdlog/spdlog.h>
#include <json.hpp>

#include <boost/lexical_cast.hpp>
#include <boost/algorithm/string.hpp>
#include <boost/format.hpp>

#include <mysql_connection.h>
#include <cppconn/driver.h>
#include <cppconn/exception.h>
#include <cppconn/resultset.h>
#include <cppconn/statement.h>

#include "common.hpp"
#include "function.hpp"

namespace machine
{
namespace sql
{

using json = nlohmann::json;

const json &travel(const json &object, const std::string &path)
{
	json::const_pointer i = &object;
	std::vector<std::string> parts;
	boost::split(parts, path, boost::is_any_of("."));
	for (auto &name : parts)
	{
		const json &current = *i;
		if (current.find(name) == current.end())
		{
			throw std::invalid_argument("unknown path: " + path);
		}
		i = &(current[name]);
	}

	return *i;
}

struct Resolver
{
	json object_;

	explicit Resolver(const json &object) : object_(object) {}

	std::string resolve(const std::string &parameter)
	{
		const std::string ref = "ref.";
		if (parameter.find(ref) != 0)
		{
            // we don't have ref. prefix
			return parameter;
		}

		const json &e = travel(object_, parameter.substr(ref.size()));
		if (e.is_number())
		{
			return boost::lexical_cast<std::string>(e.get<double>());
		}

		if (e.is_string())
		{
			return e.get<std::string>();
		}
		
		throw std::invalid_argument(e.dump());
	}
};

class Query
{
public:
	Query(const json &object, const json &data) : last_(0), area_(-1), user_(-1)
	{
		const json &body = object["body"];
		const json &parameters = body["params"];
		const json &sql = parameters["sql"];
		if (!sql.is_array() || sql.size() < 2)
		{
			throw std::invalid_argument(sql.dump());
		}

		auto i = sql.begin();
		alias_ = *i++;
		sql_ = *i++;

		Resolver r1(parameters);
		Resolver r2(json::object({ {"data", data} }));

        while (i != sql.end())
		{
			const json &e = *i++;
			if (e.is_number())
			{
				place(boost::lexical_cast<std::string>(e.get<double>()));
			}

			if (e.is_string())
			{
				const std::string &parameter = e.get<std::string>();
				std::string value = r2.resolve(r1.resolve(parameter));
				place(value);
			}

			if (e.is_object())
			{
				for (json::const_iterator i = e.begin(); i != e.end(); i++)
				{
					const json &value = i.value();
					if (value.is_number())
					{
						boost::replace_all(sql_, i.key(), boost::lexical_cast<std::string>(value.get<double>()));
					}

					if (value.is_string())
					{
						const std::string &parameter = value.get<std::string>();
						std::string value = r2.resolve(r1.resolve(parameter));
						place(i.key(), value);
					}
					
				}
			}
		}

		// TODO another way?
		auto p1 = find(data, "request.Lib");
		if (p1 != nullptr)
		{
			area_ = (*p1).get<long>();
		}

		auto p2 = find(data, "user.id");
		if (p2 != nullptr)
		{
			user_ = (*p2).get<long>();
		}
	}

	void place(const std::string &name, const std::string &value)
	{
		named_[name] = value;
	}

	void bind(std::function<std::string (const std::string &)> f)
	{
		auto t = [f](const std::string &value) {
			const char *start = value.c_str();
			char *end = nullptr;
			if (std::strtod(start, &end) == 0 && end == start)
			{
				return '\'' + f(value) + '\'';
			}
			else
			{
				return value;
			}
		};

		for (auto &value : unnamed_)
		{
			auto p = sql_.find('?', last_);
			if (p == std::string::npos)
			{
				throw std::logic_error(value);
			}
			sql_.replace(p, 1, t(value));
			last_ = p + 1;
		}

		for (auto &pair : named_)
		{
			boost::replace_all(sql_, pair.first, t(pair.second));
		}
	}

	const std::string &alias() const
	{
		return alias_;
	}

	const std::string &sql() const
	{
		return sql_;
	}

	long area() const
	{
		return area_;
	}

	long user() const
	{
		return user_;
	}

private:
	void place(const std::string &value)
	{
		unnamed_.push_back(value);
	}

	std::string alias_;
	std::string sql_;
	std::string::size_type last_;

	std::vector<std::string> unnamed_;
	std::map<std::string, std::string> named_;

	long area_;
	long user_;
};

std::string server(const Query &query, const json &parameters)
{
    auto p1 = parameters.find("server");
    if (p1 != parameters.end())
    {
        return *p1;
    }

    auto p2 = parameters["shards"];
    if (query.user() == -1)
    {
        throw std::logic_error("user id expected");
    }

    return p2[query.user() % p2.size()].get<std::string>();
}

std::string schema(const Query &query, const json &parameters)
{
    auto p1 = parameters.find("schema");
    if (p1 != parameters.end())
    {
        return *p1;
    }

    auto p2 = parameters["schema_template"];
    if (query.area() == -1)
    {
        throw std::logic_error("area expected");
    }

    return (boost::format(p2.get<std::string>()) % query.area()).str();
}

bool keep(const Query &query, const json &parameters)
{
    auto p = parameters.find("keep_connect");
    if (p != parameters.end())
    {
		auto array = *p;
        if (std::find(array.begin(), array.end(), query.area()) != array.end())
        {
            return true;
        }
    }
    return false;
}

json convert(std::unique_ptr<::sql::ResultSet> &set, unsigned int i)
{
	switch (set->getMetaData()->getColumnType(i))
	{
		case ::sql::DataType::BIT:
		case ::sql::DataType::TINYINT:
		case ::sql::DataType::SMALLINT:
		case ::sql::DataType::MEDIUMINT:
		case ::sql::DataType::INTEGER:
		case ::sql::DataType::BIGINT:
			return set->getInt64(i);

		case ::sql::DataType::REAL:
		case ::sql::DataType::DOUBLE:
			return set->getDouble(i);

		default:
			return set->getString(i);
	}
}

json convert(std::unique_ptr<::sql::ResultSet> &set)
{
	json row = json::object();
	for (unsigned int i = 1; i <= set->getMetaData()->getColumnCount(); i++)
	{
		if (set->isNull(i))
		{
			continue;
		}

		std::string key = set->getMetaData()->getColumnLabel(i);
		row[key] = convert(set, i);
	}
	return row;
}

template <typename Context>
class Database
{
public:
	std::vector<json> execute(Query &query)
	{
		auto console = spdlog::get("console");

		std::unique_ptr<::sql::Connection> connection(create(query));
		std::unique_ptr<::sql::Statement> statement(connection->createStatement());

		query.bind([&connection](const std::string &value) {
			auto p = dynamic_cast<::sql::mysql::MySQL_Connection *>(connection.get());
			return p->escapeString(value);
		});

		console->debug("executing SQL query: {0}", query.sql());
		std::unique_ptr<::sql::ResultSet> set(statement->executeQuery(query.sql()));

		std::vector<json> result;
		while (set->next())
		{
			result.emplace_back(convert(set));
		}
		return result;
	}

private:
	::sql::Connection *create(const Query &query)
	{
		const json &parameters = Context::instance().settings()["db"][query.alias()];
		const std::string &username = parameters["username"];
		const std::string &password = parameters["password"];

		auto driver = get_driver_instance();
		auto connection = driver->connect("tcp://" + server(query, parameters), username, password);
		connection->setSchema(schema(query, parameters));
		return connection;
	}
};

template <typename Context>
struct ParentSQLFunction : public Function
{
	ParentSQLFunction(const json &object, Queue &results) : Function(object, results) {}

	json execute(const json &v) const override
	{
		Query query(object_, object_["data"]);
		try
		{
			json hash = json::object();
			json order = json::array();
			
			for (json &row : Context::instance().database()->execute(query))
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
		catch (const ::sql::SQLException &e)
		{
			spdlog::get("console")->error(e.what());
			return json::object();
		}
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

		try
		{
			json rows = json::object();
			for (json &row : Context::instance().database()->execute(query))
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
		catch (const ::sql::SQLException &e)
		{
			spdlog::get("console")->error(e.what());
			return json::object();
		}
	}
};

}
}
