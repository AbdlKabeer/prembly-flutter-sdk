var imported = document.createElement("script");
imported.src = "https://js.prembly.com/v1/inline/loader/src/loadingOverlay.js";

document.head.appendChild(imported);

IdentityKYC = window.IdentityKYC || {};

IdentityKYC = (function () {
  var spinner = null;

  var eventMethod = window.addEventListener
    ? "addEventListener"
    : "attachEvent";
  eventer = window[eventMethod];
  messageEvent = "attachEvent" == eventMethod ? "onmessage" : "message";

  listenForIdentityDispatchEvent = function (options) {
    var instance = this;
    eventer(messageEvent, function (event) {
      console.log(event);
      if (
        event.data["eventInstance"] &&
        event.data.eventInstance === "identity_verification_event"
      ) {
        if (typeof options.callback === "function") {
          instance.executeCallbackFunction(event.data.data, options.callback);
        }
      }
    });
  };

  validateEmail = function (email) {
    var re =
      /^(([^<>()\[\]\\.,;:\s@"]+(\.[^<>()\[\]\\.,;:\s@"]+)*)|(".+"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/;
    return re.test(String(email).toLowerCase());
  };

  processErrorResponse = function (data) {
    var response = {};
    if (data.status === "failed") {
      response = {
        code: "E01",
        message: data.message,
        status: data.status,
      };
    } else if (data.status === "cancelled") {
      response = {
        code: "E02",
        message: "Verification Canceled",

        status: data.status,
      };
    } else {
      response = {
        code: "00",
        status: "success",
        message: data.message,
        data: data.data,
        channel: data.channel,
      };
    }
    return response;
  };

  executeCallbackFunction = function (data, callback_function) {
    var callback = evaluateFunction(callback_function);

    var element = document.getElementById("identity-frame-container");

    if (element) {
      element.parentNode.removeChild(element);
    }

    if (typeof event != "undefined" && event.data) {
      delete event.data.eventInstance;
    }

    var response = processErrorResponse(data);
    console.log(response);
    if (response.status === "success") {
      callback.call(this, response, data);
    } else {
      callback.call(this, response, null);
    }
    this.closeIframe();
  };

  closeIframe = function () {
    if (this.iframeOpen) {
      this.iframe.style.display = "none";
      this.iframe.style.visibility = "hidden";
      this.iframeOpen = false;
      document.body.style.overflow = "";
    }
  };

  function encodeQueryData(data) {
    var ret = [];
    for (var d in data) {
      if (d == "callback") {
        ret.push(d + "=" + data[d]);
        continue;
      }
      ret.push(encodeURIComponent(d) + "=" + encodeURIComponent(data[d]));
    }
    return ret.join("&");
  }

  function evaluateFunction(string) {
    try {
      return eval(string);
    } catch (err) {
      return string;
    }
  }

  validateParameters = function (defaults) {
    var parameters = {
      email: defaults.email,
      widget_id: defaults.widget_id,
      widget_key: defaults.widget_key,
      first_name: defaults.first_name,
      last_name: defaults.last_name,
      callback: defaults.callback,
    };

    var errorList = "";
    var errorUrlParamBuilder = {};

    for (var p in parameters) {
      if (!parameters[p]) {
        errorList += p + " is required \n";
        errorUrlParamBuilder[p] = p + " is required";
      }
      if (p == "callback" && typeof parameters[p] !== "function") {
        errorList += p + " must be a function \n";
        errorUrlParamBuilder[p] = p + " must be a function";
      }
    }

    if (defaults.email && !validateEmail(defaults.email)) {
      errorList += "Email is not valid \n";
      errorUrlParamBuilder["email"] = "Email is not valid";
    }

    if (!defaults.widget_id) {
      errorList += "widget_id cannot be empty  \n";
      errorUrlParamBuilder["widget_id"] = "widget_id cannot be empty ";
    }

    if (!defaults.widget_key) {
      errorList += "widget_key cannot be empty  \n";
      errorUrlParamBuilder["widget_key"] = "widget_key cannot be empty ";
    }

    if (errorList.length > 0) {
      if (typeof parameters["callback"] === "function") {
        var callback = evaluateFunction(parameters["callback"]);
        callback.call(
          this,
          {
            code: "E00",
            message: "Validation failed",
            data: errorUrlParamBuilder,
          },
          null
        );
      } else {
        console.error("Callback function is required");
      }
      return false;
    }

    return true;
  };

  verify = function (params = {}) {
    var widget_id = params.widget_id;
    var widget_key = params.widget_key;
    var first_name = params.first_name;
    var last_name = params.last_name;
    var email = params.email;
    var phone = params.phone;
    var metadata = params.metadata;
    var callback = params.callback;

    spinner = loadingOverlay().activate();

    var options = {
      widget_id: widget_id,
      widget_key: widget_key,
      last_name: last_name,
      first_name: first_name,
      email: email,
      phone: phone,
      metadata: metadata,
      callback: callback,
    };

    listenForIdentityDispatchEvent(options);

    // Updated API endpoint for your backend
    var apiBaseUrl =
      "https://backend.prembly.com/api/v1/checker-widget/sdk/sessions/initiate/";

    //validate the parameters recieved
    if (validateParameters(options)) {
      //initialize transaction
      var xhr = new XMLHttpRequest();
      xhr.open("POST", apiBaseUrl, true);
      xhr.setRequestHeader("Content-type", "application/json");

      xhr.onreadystatechange = function () {
        if (xhr.readyState == XMLHttpRequest.DONE) {
          if (xhr.status == 200 || xhr.status == 201) {
            var response = JSON.parse(xhr.response);
            console.log("Session created:", response);

            // Extract session_id from response
            var session_id = response.data.session_id;

            // Load iframe with CloudFront URL
            loadIframeWithSession(session_id, options);
          } else {
            loadingOverlay().cancel(spinner);
            var error = JSON.parse(xhr.responseText);

            callback.call(
              this,
              {
                code: "E00",
                message: error.message || "Failed to initialize session",
                errors: error.errors || error,
              },
              null
            );
          }
        }
      };

      var request_data = JSON.stringify({
        first_name: first_name,
        last_name: last_name,
        email: email,
        phone: phone,
        widget_id: widget_id,
        widget_key: widget_key,
        metadata: metadata || {},
      });

      xhr.send(request_data);
    } else {
      //validation field....stop loader
      loadingOverlay().cancel(spinner);
    }
  };

  loadIframeWithSession = function (session_id, options) {
    var cloudFrontUrl = "https://sdk-live.prembly.com/?session=" + session_id + "&has_callback=" + (typeof options.callback === "function");

    this.div = document.createElement("div");
    this.div.id = "identity-frame-container";
    this.div.setAttribute(
      "style",
      "position:fixed; left: 0; right: 0; bottom: 0; top: 0px; z-index: 99999;width:100%;height:100%,opacity:0.7"
    );
    this.iframe = document.createElement("iframe");
    this.iframe.src = cloudFrontUrl;
    this.iframe.allow = "camera; microphone; clipboard-read; clipboard-write;";
    this.iframe.onload = () => {
      loadingOverlay().cancel(spinner);
    };
    this.iframe.id = "identity-frame-component";
    this.iframe.setAttribute(
      "style",
      "z-index: 2147483647;display: block;border: 0px none transparent; overflow-x: hidden; overflow-y: auto; visibility: visible; margin: 0px; padding: 0px; -webkit-tap-highlight-color: transparent; @media only screen and (max-width: 600px) {margin-bottom: 30%}; height: 100%;width:100%"
    );
    this.iframeOpen = true;
    this.div.appendChild(this.iframe);
    document.body.appendChild(this.div);
  };

  return {
    verify: verify,
  };
})();
