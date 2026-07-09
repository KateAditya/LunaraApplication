const fs = require('fs');
const pdf = require('pdf-parse/lib/pdf-parse.js');

let dataBuffer = fs.readFileSync('e:\\lunara_app\\lunara_app\\LUNARA SUBCRIPCTIONS.pdf');

pdf(dataBuffer).then(function(data) {
    console.log(data.text);
}).catch(err => {
    console.error(err);
});
