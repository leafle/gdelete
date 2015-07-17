# gdelete
Simple ruby script that deletes emails using the GMail API.

So far it's been a complete failure.  Sending delete requests in batches any larger than 15 at a time results in 429 (Too Many Requests) errors from the server.  My current theory is that Google's 250 requests per user per second quota is actuallly implemented in smaller periods (ie. 25 requests per user per 0.1 seconds) and by sending in batches all of the rate-limiting code is being hit at once.

I might test out this theory with some threading but I haven't gotten to that yet.
