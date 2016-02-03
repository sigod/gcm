/**
	Google Cloud Messaging (GCM) for D

	Copyright: © 2016 sigod
	License: Subject to the terms of the MIT license, as written in the included LICENSE file.
	Authors: sigod
*/
module gcm;

private {
	import core.time : weeks;
	import std.json;
	import std.range : isInputRange, ElementType;
	import std.typecons : Nullable;
}

/// Convenience function for GCMessage. Converts T to JSONValue.
GCMessage gcmessage(T = JSONValue)(T data = T.init)
{
	GCMessage ret;
	ret.data = convert(data);
	return ret;
}
/// ditto
GCMessage gcmessage(T = JSONValue)(GCMNotification ntf, T data = T.init)
{
	GCMessage ret;
	ret.notification = ntf;
	ret.data = convert(data);
	return ret;
}

enum GCMPriority
{
	normal = "normal",
	high = "high"
}

struct GCMessage
{
	/// This parameter specifies the recipient of a message.
	package string to;

	/// This parameter specifies a list of devices (registration tokens, or IDs) receiving a multicast message.
	package const(string)[] registration_ids;

	/// This parameter identifies a group of messages that can be collapsed.
	string collapse_key;

	/// Sets the priority of the message. Valid values are "normal" and "high".
	GCMPriority priority;

	/// When a notification or message is sent and this is set to true, an inactive client app is awoken.
	Nullable!bool content_available;

	/// When this parameter is set to true, it indicates that the message should not be sent until the device becomes active.
	bool delay_while_idle;

	/// This parameter specifies how long (in seconds) the message should be kept in GCM storage if the device is offline.
	int time_to_live = weeks(4).total!"seconds";

	/**
		This parameter specifies the package name of the application where
		the registration tokens must match in order to receive the message.
	*/
	string restricted_package_name;

	/// This parameter, when set to true, allows developers to test a request without actually sending a message.
	bool dry_run;

	/// This parameter specifies the key-value pairs of the notification payload.
	Nullable!GCMNotification notification;

	/// This parameter specifies the key-value pairs of the message's payload.
	JSONValue data;
}

struct GCMNotification
{
	/// Indicates notification title. This field is not visible on iOS phones and tablets.
	string title;

	/// Indicates notification body text.
	string body_;

	/// Indicates notification icon. On Android: sets value to `myicon` for drawable resource `myicon.png`.
	string icon;

	/// Indicates sound to be played. Supports only default currently.
	string sound;

	/// Indicates the badge on client app home icon.
	string badge;

	/**
		Indicates whether each notification message results in a new entry on the notification center on Android.
		If not set, each request creates a new notification. If set, and a notification with the same tag is already
		being shown, the new notification replaces the existing one in notification center.
	*/
	string tag;

	/// Indicates color of the icon, expressed in #rrggbb format
	string color;

	/// The action associated with a user click on the notification.
	string click_action;

	/// Indicates the key to the body string for localization.
	string body_loc_key;

	/// Indicates the string value to replace format specifiers in body string for localization.
	@asString
	string[] body_loc_args;

	/// Indicates the key to the title string for localization.
	string title_loc_key;

	/// Indicates the string value to replace format specifiers in title string for localization.
	@asString
	string[] title_loc_args;
}

///
struct GCMResponseResult
{
	string message_id;
	string registration_id;
	string error;
}

///
struct GCMResponse
{
	string message_id;
	string error;

	long multicast_id;
	long success;
	long failure;
	long canonical_ids;
	GCMResponseResult[] results;
}

/**
 * Wrapper around `sendMulticast` since GCM's answers inconsistent
 * for direct messages. Sometimes you get plain text instead of JSON.
 */
Nullable!MulticastMessageResponse sendDirect(string key, string receiver, GCMessage message)
{
	//TODO: convert into proper *MessageResponce?
	return sendMulticast(key, [receiver], message);
}

///
struct DeviceGroup
{
	string api_key;
	string sender_id;
	string notification_key_name;
	string notification_key;
}

/// Functions for managing device groups
bool create(ref DeviceGroup group, string[] registration_ids)
{
	if (auto response = groupOperation(group, "create", registration_ids)) {
		auto json = response.parseJSON();

		if (auto key = "notification_key" in json.object) {
			group.notification_key = (*key).str();
			return true;
		}
	}

	return false;
}

/// ditto
bool add(DeviceGroup group, string[] registration_ids)
{
	return groupOperation(group, "add", registration_ids) !is null;
}

/// ditto
bool remove(DeviceGroup group, string[] registration_ids)
{
	return groupOperation(group, "remove", registration_ids) !is null;
}

struct DeviceGroupResponse
{
	byte success;
	byte failure;
	string[] failed_registration_ids;
}

Nullable!DeviceGroupResponse sendGroup(DeviceGroup group, GCMessage message)
{
	return sendGroup(group.api_key, group.notification_key, message);
}

Nullable!DeviceGroupResponse sendGroup(string key, string to, GCMessage message)
{
	if (auto response = send(key, to, message)) {
		DeviceGroupResponse ret;

		if (response.parse(ret))
			return cast(Nullable!DeviceGroupResponse)ret;
	}

	return Nullable!DeviceGroupResponse.init;
}

struct TopicMessageResponse
{
	long message_id;
	string error;
}

Nullable!TopicMessageResponse sendTopic(string key, string topic, GCMessage message)
{
	import std.algorithm : startsWith;
	assert(topic.startsWith("/topics/"), "all topics must start with '/topics/'");

	if (auto response = send(key, topic, message)) {
		TopicMessageResponse ret;

		if (response.parse(ret))
			return cast(Nullable!TopicMessageResponse)ret;
	}

	return Nullable!TopicMessageResponse.init;
}

struct MulticastMessageResponse
{
	long multicast_id;
	short success;
	short failure;
	short canonical_ids;
	MulticastMessageResult[] results;
}

struct MulticastMessageResult
{
	string message_id;
	string registration_id;
	string error;
}

Nullable!MulticastMessageResponse sendMulticast(Range)(string key, Range registration_ids, GCMessage message)
	if (isInputRange!Range && is(ElementType!Range : const(char)[]))
{
	import std.array : array;
	//TODO: some way to avoid allocation?
	auto ids = registration_ids.array;

	assert(ids.length <= 1000, "number of registration_ids currently limited to 1000, see #2");

	message.registration_ids = ids;

	string _null = null;

	if (auto response = send(key, _null, message)) {
		MulticastMessageResponse ret;

		if (response.parse(ret))
			return cast(Nullable!MulticastMessageResponse)ret;
	}

	return Nullable!MulticastMessageResponse.init;
}

///
enum asString;

private:

import std.net.curl;

char[] send(string key, string to, GCMessage message)
{
	HTTP client = HTTP();

	client.addRequestHeader("Content-Type", "application/json");
	client.addRequestHeader("Authorization", "key=" ~ key);

	message.to = to;

	try {
		return post("https://gcm-http.googleapis.com/gcm/send", convert(message).toString(), client);
	}
	catch (Exception e) {
		import std.stdio : stderr;
		stderr.writeln("[GCM] request failed: ", e);

		return null;
	}
}

char[] groupOperation(DeviceGroup group, string operation, string[] registration_ids)
{
	assert(registration_ids.length);

	static struct Request
	{
		string operation;
		string notification_key_name;
		string notification_key;
		string[] registration_ids;
	}

	Request request = void;
	request.operation = operation;
	request.notification_key_name = group.notification_key_name;
	if (operation != "create") request.notification_key = group.notification_key;
	request.registration_ids = registration_ids;

	HTTP client = HTTP();

	client.addRequestHeader("Content-Type", "application/json");
	client.addRequestHeader("Authorization", "key=" ~ group.api_key);
	client.addRequestHeader("project_id", group.sender_id);

	try {
		return post("https://android.googleapis.com/gcm/notification", convert(request).toString(), client);
	}
	catch (Exception e) {
		import std.stdio : stderr;
		stderr.writeln("[GCM] request failed: ", e);

		return null;
	}
}

alias Alias(alias a) = a;

string stripName(string name)()
{
	import std.algorithm : endsWith;

	static if (name.endsWith('_'))
		return name[0 .. $ - 1];
	else
		return name;
}

template stripNullable(T)
{
	static if (is(T == Nullable!V, V))
		alias stripNullable = V;
	else
		alias stripNullable = T;
}

template isISOExtStringSerializable(T)
{
	enum bool isISOExtStringSerializable =
		is(typeof(T.init.toISOExtString()) == string) && is(typeof(T.fromISOExtString("")) == T);
}

static if (__VERSION__ < 2068) {
	//TODO: remove in future versions of compiler
	template hasUDA(alias symbol, alias attribute)
	{
		import std.typetuple : staticIndexOf;

		enum bool hasUDA = staticIndexOf!(attribute, __traits(getAttributes, symbol)) != -1;
	}
}
else {
	import std.traits : hasUDA;
}

//TODO: support classes
JSONValue convert(T)(T value)
{
	import std.traits : isSomeFunction, isTypeTuple;

	alias Type = stripNullable!T;

	JSONValue[string] ret;

	foreach (field_name; __traits(allMembers, Type)) {
		alias Field = Alias!(__traits(getMember, Type, field_name));

		static if (!isTypeTuple!Field && !isSomeFunction!Field) {
			alias FieldType = typeof(__traits(getMember, Type, field_name));
			alias FieldN = stripNullable!FieldType;

			static if (__traits(compiles, { if (__traits(getMember, value, field_name).isNull) {} })) {
				if (__traits(getMember, value, field_name).isNull)
					continue;
			}
			else {
				if (__traits(getMember, value, field_name) == __traits(getMember, Type.init, field_name))
					continue;
			}

			JSONValue json = void;

			static if (__traits(compiles, { auto v = JSONValue(__traits(getMember, value, field_name)); })) {
				json = JSONValue(__traits(getMember, value, field_name));
			}
			else static if (isISOExtStringSerializable!FieldN) {
				json = __traits(getMember, value, field_name).toISOExtString();
			}
			else static if (is(FieldN == struct)) {
				json = convert(__traits(getMember, value, field_name));
			}
			else
				static assert(false, FieldN.stringof ~ " not supported");

			static if (hasUDA!(Field, asString)) {
				json = JSONValue(json.toString());
			}

			ret[stripName!field_name] = json;
		}
	}

	return JSONValue(ret);
}

bool parse(T)(in char[] response, out T ret)
{
	try {
		ret = response.parseJSON.parse!T;

		return true;
	}
	catch (JSONException e) {
		import std.stdio : stderr;
		stderr.writeln("[GCM] parsing failed: ", e);

		return false;
	}
}

T parse(T)(JSONValue json)
{
	import std.array : array;
	import std.algorithm : map;
	import std.traits : isIntegral;

	assert(json.type == JSON_TYPE.OBJECT);

	T ret;

	foreach (field_name; __traits(allMembers, T)) {
		alias FieldType = typeof(__traits(getMember, T, field_name));

		if (auto field = field_name in json.object) {
			static if (isIntegral!FieldType) {
				if ((*field).type == JSON_TYPE.INTEGER)
					__traits(getMember, ret, field_name) = cast(FieldType)(*field).integer;
			}
			else static if (is(FieldType == string)) {
				if ((*field).type == JSON_TYPE.STRING)
					__traits(getMember, ret, field_name) = (*field).str;
			}
			else static if (is(FieldType == E[], E)) {
				if ((*field).type == JSON_TYPE.ARRAY) {
					static if (is(E == string))
						__traits(getMember, ret, field_name) = (*field).array.map!(e => e.str).array;
					else static if (is(E == struct))
						__traits(getMember, ret, field_name) = (*field).array.map!(e => e.parse!E).array;
				}
			}
		}
	}

	return ret;
}

unittest {
	auto r = `{"success":1, "failure":2, "failed_registration_ids":["regId1", "regId2"]}`;
	auto expected = DeviceGroupResponse(1, 2, ["regId1", "regId2"]);

	DeviceGroupResponse result;
	assert(r.parse!DeviceGroupResponse(result));

	assert(result == expected);
}

unittest {
	static struct Inner
	{
		int field0;
	}
	static struct Outer
	{
		int field0;
		Inner[] field1;
	}

	auto r = `{"field0":3, "field1":[{"field0":0}, {"field0":1}, {"field0":2}]}`;
	auto expected = Outer(3, [Inner(0), Inner(1), Inner(2)]);

	Outer result;
	assert(r.parse(result));

	assert(result == expected);
}

T get(T)(JSONValue json, string name)
{
	assert(json.type == JSON_TYPE.OBJECT);

	if (auto value = name in json.object) {
		static if (is(T == string)) {
			if ((*value).type == JSON_TYPE.STRING) return (*value).str;

			if ((*value).type == JSON_TYPE.INTEGER) {
				import std.conv : to;

				return (*value).integer.to!string;
			}
		}
		else static if (is(T == long)) {
			if ((*value).type == JSON_TYPE.INTEGER) return (*value).integer;
		}
		else
			static assert(false);
	}

	return T.init;
}
