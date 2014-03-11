
var ami = "http://amidemo.ctac.nl/sap/ctacv2/api/abap-cli?sap-user=#1&sap-password=#2&sap-client=#3";
ami = ami.replace("#1", process.argv[2]);
ami = ami.replace("#2", process.argv[3]);
ami = ami.replace("#3", process.argv[4]);		

var http    = require('http');
var fs      = require('fs');
var request = require('request');

// Let's make sure the program has the total number of required arguments first
fs.readFile( process.argv[5], 'utf8', function(err, data) {
	if (err) {
		console.error(err);
	} else {
		request(
			{
				uri: ami,
				method: "POST",
				body : data,
			},
			function(error, response, body) {
				console.log(body);
			}
		);
	}
});

