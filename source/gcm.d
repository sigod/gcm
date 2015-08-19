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
	string title;
	string icon;
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
