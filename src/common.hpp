#pragma once

#include <json.hpp>

#include <boost/algorithm/string.hpp>

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
            // TODO merge array?
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

}
