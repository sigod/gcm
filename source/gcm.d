/**
	Google Cloud Messaging (GCM) for D

	Copyright: © 2015 sigod
	License: Subject to the terms of the MIT license, as written in the included LICENSE file.
	Authors: sigod
*/
module gcm;

private {
	import core.time : weeks;
	import std.json;
	import std.typecons : Nullable;
}

/// Convenience function for GCMessage!Data
auto gcmessage(T = JSONValue)(string to, T data = T.init)
{
	GCMessage!T ret;
	ret.to = to;
	ret.data = data;
	return ret;
}

enum GCMPriority
{
	normal = "normal",
	high = "high"
}

struct GCMessage(Data = JSONValue)
{
	/// This parameter specifies the recipient of a message.
	string to;

	/// This parameter specifies a list of devices (registration tokens, or IDs) receiving a multicast message.
	string[] registration_ids;

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
	Data data;
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
	string[] body_loc_args;

	/// Indicates the key to the title string for localization.
	string title_loc_key;

	/// Indicates the string value to replace format specifiers in title string for localization.
	string[] title_loc_args;
}

class GCM
{
	private string m_key;

	this(string key)
	{
		m_key = key;
	}

	void send(T)(GCMessage!T message)
	{
		import std.net.curl;

		HTTP client = HTTP();

		// Windows issues
		//client.handle.set(CurlOption.ssl_verifypeer, 0);

		client.addRequestHeader("Content-Type", "application/json");
		client.addRequestHeader("Authorization", "key=" ~ m_key);

		post("https://gcm-http.googleapis.com/gcm/send", convert(message).toString(), client);
	}
}

private:

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

//TODO: support classes
//TODO: `required` fields
//TODO: `asString` fields
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

			static if (__traits(compiles, { auto v = JSONValue(__traits(getMember, value, field_name)); })) {
				ret[stripName!field_name] = JSONValue(__traits(getMember, value, field_name));
			}
			else static if (isISOExtStringSerializable!FieldN) {
				ret[stripName!field_name] = __traits(getMember, value, field_name).toISOExtString();
			}
			else static if (is(FieldN == struct)) {
				ret[stripName!field_name] = convert(__traits(getMember, value, field_name));
			}
			else
				static assert(false, FieldN.stringof ~ " not supported");
		}
	}

	return JSONValue(ret);
}
