function evaluateFunction(string) {
  try {
    return eval(string);
  } catch (err) {
    return string;
  }
}

var defaults = {
  callback: function(res) { console.log(res); }
};

var parameters = {
  callback: defaults.callback
};

console.log(typeof parameters["callback"]);

if ("callback" == "callback" && typeof parameters["callback"] !== "function") {
  console.log("must be a function");
} else {
  console.log("it is a function");
}
