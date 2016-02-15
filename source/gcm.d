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
	auto request = finalMessage(message, to);

	if (auto response = send(key, request)) {
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

	auto request = finalMessage(message, topic);

	if (auto response = send(key, request)) {
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
	//assert(ids.length <= 1000, "number of registration_ids currently limited to 1000, see #2");

	auto request = finalMessage(message, registration_ids);

	if (auto response = send(key, request)) {
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

string finalMessage(in GCMessage message, in char[] to)
{
	auto json = convert(message);
	json["to"] = to;
	return json.toString();
}

string finalMessage(Range)(in GCMessage message, Range ids)
{
	import std.algorithm : map;
	import std.array : array;

	auto json = convert(message);
	// this way JSONValue will use provided array instead of allocating new one
	json["registration_ids"] = ids.map!(e => JSONValue(e)).array;
	return json.toString();
}

char[] send(string key, in char[] message)
{
	HTTP client = HTTP();

	client.addRequestHeader("Content-Type", "application/json");
	client.addRequestHeader("Authorization", "key=" ~ key);

	try {
		return post("https://gcm-http.googleapis.com/gcm/send", message, client);
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

JSONValue convert(T)(T value)
{
	import std.algorithm : each, map;
	import std.array : array;
	import std.conv : to;
	import std.traits : hasUDA, isAssociativeArray, isSomeFunction;

	alias Type = stripNullable!T;

	static if (is(T == Nullable!Type)) {
		if (value.isNull) return JSONValue(null);
	}
	else static if (is(T == class)) {
		if (value is null) return JSONValue(null);
	}

	static if (is(Type == JSONValue)) {
		return value;
	}
	else static if (is(typeof(JSONValue(value)))) {
		return JSONValue(value);
	}
	else static if (isISOExtStringSerializable!Type) {
		return JSONValue(value.toISOExtString());
	}
	else static if (isInputRange!Type) {
		return JSONValue(value.map!(e => convert(e)).array);
	}
	else static if (isAssociativeArray!Type) {
		JSONValue[string] object;

		value.byKeyValue().each!((pair) {
			object[pair.key.to!string] = convert(pair.value);
		});

		return JSONValue(object);
	}
	else static if (is(Type == struct) || is(Type == class)) {
		JSONValue[string] object;

		foreach (field_name; __traits(derivedMembers, Type)) {
			alias FieldType = typeof(__traits(getMember, value, field_name));

			//TODO: support getters?
			static if (!isSomeFunction!FieldType) {
				auto field = convert(__traits(getMember, value, field_name));

				static if (hasUDA!(__traits(getMember, Type, field_name), asString))
					field = JSONValue(field.toString());

				object[stripName!field_name] = field;
			}
		}

		return JSONValue(object);
	}
	else
		static assert(false, Type.stringof ~ " not supported");
}

unittest
{
	assert(convert(Nullable!int.init) == parseJSON(`null`));
	assert(convert(Nullable!int(42)) == parseJSON(`42`));

	assert(convert(42) == parseJSON(`42`));
	assert(convert("42") == parseJSON(`"42"`));
	assert(convert(4.2) == parseJSON(`4.2`));
}

unittest
{
	import std.datetime : SysTime, UTC;
	assert(convert(SysTime(0, UTC())).toString() == `"0001-01-01T00:00:00Z"`);
}

unittest
{
	import std.algorithm : map;
	assert(convert([1, 2, 3].map!(e => e*3)) == parseJSON(`[3,6,9]`));
}

unittest
{
	assert(convert([1:2, 2:4, 3:6]) == parseJSON(`{"1":2,"2":4,"3":6}`));
}

unittest
{
	static struct Inner
	{
		int a;
	}
	static struct S
	{
		Inner inner;
	}
	assert(convert(S(Inner(42))) == parseJSON(`{"inner":{"a":42}}`));
}

unittest
{
	static class C
	{
		int a;
		this(int v) { a = v; }
	}
	assert(convert(new C(42)) == parseJSON(`{"a":42}`));
}

unittest
{
	static struct S
	{
		int in_;
	}
	assert(convert(S(1)) == parseJSON(`{"in":1}`));
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

		if (auto field = stripName!field_name in json.object) {
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

unittest
{
	static struct S
	{
		int in_;
	}
	assert(parseJSON(`{"in":1}`).parse!S.in_ == 1);
}
