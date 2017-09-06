#pragma once

#include <memory>
#include <sstream>

#include <spdlog/spdlog.h>
#include <json.hpp>

#include <boost/lexical_cast.hpp>
#include <boost/algorithm/string.hpp>

#include <mysql_connection.h>
#include <cppconn/driver.h>
#include <cppconn/exception.h>
#include <cppconn/resultset.h>
#include <cppconn/statement.h>

#include "function.hpp"

namespace machine
{
namespace sql
{

using json = nlohmann::json;

template <typename Context>
class Pool
{
public:
	std::shared_ptr<::sql::Connection> get(const std::string &alias)
	{
		const json &parameters = Context::instance().settings()["db"][alias];
		const std::string &server = parameters["server"];
		const std::string &username = parameters["username"];
		const std::string &password = parameters["password"];
		const std::string &schema = parameters["schema"];

		auto driver = get_driver_instance();
		std::shared_ptr<::sql::Connection> connection(driver->connect("tcp://" + server, username, password));
		connection->setSchema(schema);
		return connection;
	}
};

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
			throw std::invalid_argument(name);
		}
		i = &(current[name]);
	}

	return *i;
}

struct Resolver
{
	const json &object_;

	Resolver(const json &object) : object_(object) {}

	std::string resolve(const std::string &parameter)
	{
		const std::string ref = "ref.";
		if (parameter.find(ref) != 0)
		{
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
	Query(const json &object) : last_(0)
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
		Resolver r2(object);
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
	}

	void place(const std::string &name, const std::string &value)
	{
		boost::replace_all(sql_, name, value);
	}

	const std::string &alias() const
	{
		return alias_;
	}

	const std::string &sql() const
	{
		return sql_;
	}

private:
	void place(const std::string &value)
	{
		auto p = sql_.find("?", last_);
		if (p == std::string::npos)
		{
			throw std::logic_error(value);
		}
		sql_.replace(p, 1, value);
		last_ = p + 1;
	}

	std::string alias_;
	std::string sql_;
	std::string::size_type last_;
};

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
struct ParentSQLFunction : public Function
{
	ParentSQLFunction(const json &object) : Function(object) {}

	json execute(const json &v) const override
	{
		Query query(object_);
		auto console = spdlog::get("console");
		console->debug("executing SQL query: {0}", query.sql());
		try
		{
			std::shared_ptr<::sql::Connection> connection = Context::instance().pool()->get(query.alias());
			std::unique_ptr<::sql::Statement> statement(connection->createStatement());
			std::unique_ptr<::sql::ResultSet> set(statement->executeQuery(query.sql()));
			json hash = json::object();
			while (set->next())
			{
				json row = convert(set);
				auto p = row.find("id");
				if (p == row.end())
				{
					throw std::logic_error("id not found");
				}
				std::string key = boost::lexical_cast<std::string>(p->get<long>());
				hash[key] = row;
			}
			json list = json::object();
			list["hash_by_id"] = hash;

			json result = json::object();
			result["list"] = list;

			json data(v);
			data["result"] = result;

			// body => params => list_path

			return data;
		}
		catch (const ::sql::SQLException &e)
		{
			console->error(e.what());
			return json::object();
		}
	}
};

template <typename Context>
struct ChildSQLFunction : public Function
{
	ChildSQLFunction(const json &object) : Function(object) {}

	json execute(const json &v) const override
	{
		Query query(object_);

		json data(v);
		json &hash = data["result"]["list"]["hash_by_id"];

		std::stringstream t;
		int counter = 0;
		for (json::iterator i = hash.begin(); i != hash.end(); i++)
		{
			t << i.key();
			if (counter++ != hash.size() - 1)
			{
				t << ",";
			}
		}
		query.place(":ids", t.str());

		auto console = spdlog::get("console");
		console->debug("executing SQL query: {0}", query.sql());
		try
		{
			std::shared_ptr<::sql::Connection> connection = Context::instance().pool()->get(query.alias());
			std::unique_ptr<::sql::Statement> statement(connection->createStatement());
			std::unique_ptr<::sql::ResultSet> set(statement->executeQuery(query.sql()));
			json rows = json::object();
			while (set->next())
			{
				json row = convert(set);
				auto p1 = row.find("id");
				if (p1 == row.end())
				{
					throw std::logic_error("id not found");
				}

				std::string key = boost::lexical_cast<std::string>(p1->get<long>());
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
				json &row = hash[i.key()];
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
					const json &path = object_["body"]["hash_of_lists"];
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
			}

			return data;
		}
		catch (const ::sql::SQLException &e)
		{
			console->error(e.what());
			return json::object();
		}
	}
};

}
}
