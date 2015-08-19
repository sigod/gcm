/**
	Google Cloud Messaging (GCM) for D

	Copyright: © 2015 sigod
	License: Subject to the terms of the MIT license, as written in the included LICENSE file.
	Authors: sigod
*/
module gcm;

private {
	import std.json;
	import std.typecons : Nullable;
}

struct GCMRequest
{
	string to;

	bool dry_run;

	Nullable!GCMNotification notification;

	JSONValue data;

	package JSONValue toJSON()
	{
		JSONValue msg = ["to": to];

		if (dry_run)
			msg.object["dry_run"] = true;

		if (!notification.isNull)
			msg.object["notification"] = ["title": notification.title, "icon": notification.icon];

		if (!data.isNull)
			msg.object["data"] = data;

		return msg;
	}
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

	JSONValue toJSON()
	{
		assert(icon.length, "icon is required");

		import std.traits : isSomeFunction;
		import std.algorithm : endsWith;

		string[string] object;

		foreach (field_name; __traits(allMembers, typeof(this))) {
			alias field = Alias!(__traits(getMember, typeof(this), field_name));

			static if (!isSomeFunction!field) {
				if (field.length) {
					static if (is(typeof(field) == string)) {
						static if (field_name.endsWith('_'))
							object[field_name[0 .. $-1]] = field;
						else
							object[field_name] = field;
					}
					else static if (is(typeof(field) == string[])) {
						// just speculation for now, can't find usage examples
						object[field_name] = JSONValue(field).toString();
					}
					else static assert(false, field_name ~ " has unsupported type");
				}
			}
		}

		return JSONValue(object);
	}
}

class GCM
{
	private string m_key;

	this(string key)
	{
		m_key = key;
	}

	void send(GCMRequest request)
	{
		import std.net.curl;

		HTTP client = HTTP();

		// Windows issues
		//client.handle.set(CurlOption.ssl_verifypeer, 0);

		client.addRequestHeader("Content-Type", "application/json");
		client.addRequestHeader("Authorization", "key=" ~ m_key);

		post("https://gcm-http.googleapis.com/gcm/send", request.toJSON().toString(), client);
	}
}

private:

alias Alias(alias a) = a;
