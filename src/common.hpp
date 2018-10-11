#pragma once

#include <json.hpp>

#include <boost/algorithm/string.hpp>
#include <boost/lexical_cast.hpp>

namespace machine
{
using json = nlohmann::json;

void merge(const json &from, json &to)
{
    for (json::const_iterator j = from.begin(); j != from.end(); j++)
    {
        if (j.value().is_object())
        {
            auto p = to.find(j.key());
            if (p != to.end())
            {
                merge(j.value(), *p);
            }
            else
            {
                to[j.key()] = j.value();
            }
        }
        else if (j.value().is_array())
        {
            auto p = to.find(j.key());
            if (p != to.end())
            {
                const json &input = j.value();
                json &output = *p;
                for (size_t i = 0; i < input.size(); i++)
                {
                    if (i < output.size())
                    {
                        merge(input[i], output[i]);
                    }
                    else
                    {
                        output.push_back(input[i]);
                    }
                }
            }
            else
            {
                to[j.key()] = j.value();
            }
        }
        else
        {
            to[j.key()] = j.value();
        }
    }
}

json::const_pointer find(const json &object, const std::string &path)
{
    json::const_pointer i = &object;
    std::vector<std::string> parts;
    boost::split(parts, path, boost::is_any_of("."));
    for (auto &name : parts)
    {
        const json &current = *i;
        if (current.find(name) == current.end())
        {
            return nullptr;
        }
        i = &(current[name]);
    }

    return i;
}

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

}
