/* vim: set ai noet ts=4 sw=4 tw=115: */
//
// Copyright (c) 2014 Nikolay Zapolnov (zapolnov@gmail.com).
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
#import "parse_twitter.h"
#import <yip-imports/ios/image.h>
#import <Social/Social.h>

void parseTwitterAuth(UIView * parentView, void (^ callback)(enum TwitterAuthResult result, PFUser * user))
{
	twitterAuth(parentView, ^(enum TwitterAuthResult result, ACAccount * account, NSDictionary * response) {
		if (result != TWITTER_AUTH_SUCCESS)
		{
			[PFUser logOut];
			if (callback)
				callback(result, nil);
			return;
		}

		NSString * userID = response[@"user_id"];
		NSString * screenName = response[@"screen_name"];
		NSString * oauthToken = response[@"oauth_token"];
		NSString * oauthTokenSecret = response[@"oauth_token_secret"];
		[PFTwitterUtils logInWithTwitterId:userID screenName:screenName authToken:oauthToken
			authTokenSecret:oauthTokenSecret block:^(PFUser * user, NSError * error)
		{
			if (!user || error)
			{
				[PFUser logOut];
				if (callback)
					callback(TWITTER_AUTH_FAILED, nil);
				return;
			}

			NSURL * url = [NSURL URLWithString:@"https://api.twitter.com/1.1/users/show.json"];
			NSDictionary * params = @{ @"user_id" : userID };

			SLRequest * request = [SLRequest requestForServiceType:SLServiceTypeTwitter
				requestMethod:SLRequestMethodGET URL:url parameters:params];
			request.account = account;
			[request performRequestWithHandler:^(NSData * data, NSHTTPURLResponse * response, NSError * error) {
				if (error || !data)
				{
					[PFUser logOut];
					if (callback)
						callback(TWITTER_AUTH_FAILED, nil);
					return;
				}

				NSString * avatarURL = nil;
				@try
				{
					id json = [NSJSONSerialization JSONObjectWithData:data
						options:NSJSONReadingAllowFragments error:nil];

					avatarURL = json[@"profile_image_url"];
					avatarURL = [avatarURL stringByReplacingOccurrencesOfString:@"_normal." withString:@"."];
				}
				@catch (id e)
				{
					NSLog(@"Unable to fetch Twitter avatar URL: %@", e);
					[PFUser logOut];
					if (callback)
						callback(TWITTER_AUTH_FAILED, nil);
					return;
				}

				@try
				{
					NSString * name = screenName;
					if (name.length == 0 || [name characterAtIndex:0] != '@')
						name = [@"@" stringByAppendingString:name];

					user[@"displayName"] = name;
					user[@"displayNameLower"] = [name lowercaseString];
					user[@"twitterID"] = userID;
					user[@"twitterAvatarURL"] = (avatarURL ? avatarURL : [NSNull null]);
				}
				@catch (id e)
				{
					NSLog(@"Unable to store Twitter authentication data in PFUser: %@", e);
					[PFUser logOut];
					if (callback)
						callback(TWITTER_AUTH_FAILED, nil);
					return;
				}

				[user saveInBackgroundWithBlock:^(BOOL succeeded, NSError * error) {
					if (!succeeded || error)
					{
						[PFUser logOut];
						if (callback)
							callback(TWITTER_AUTH_FAILED, nil);
						return;
					}

					if (callback)
						callback(TWITTER_AUTH_SUCCESS, user);
				}];
			}];
		}];
	});
}

BOOL parseIsUserTwitterLinked(PFUser * user)
{
	NSString * id = user[@"twitterID"];
	return (id.length != 0);
}

void parseGetAvatarForTwitterUser(PFUser * user, void (^ callback)(UIImage * image))
{
	NSString * url = user[@"twitterAvatarURL"];

	if (url.length == 0)
	{
		if (callback)
			callback(nil);
		return;
	}

	iosAsyncDownloadImage(url, callback);
}
