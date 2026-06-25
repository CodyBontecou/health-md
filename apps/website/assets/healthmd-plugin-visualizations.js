// Generated from obsidian-health-md src/visualizations. Do not edit directly.
// Run: npm run visualizations:bundle
(() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));

  // ../../obsidian-plugin-hub/obsidian-health-md/node_modules/leaflet/dist/leaflet-src.js
  var require_leaflet_src = __commonJS({
    "../../obsidian-plugin-hub/obsidian-health-md/node_modules/leaflet/dist/leaflet-src.js"(exports, module) {
      (function(global, factory) {
        typeof exports === "object" && typeof module !== "undefined" ? factory(exports) : typeof define === "function" && define.amd ? define(["exports"], factory) : (global = typeof globalThis !== "undefined" ? globalThis : global || self, factory(global.leaflet = {}));
      })(exports, (function(exports2) {
        "use strict";
        var version = "1.9.4";
        function extend(dest) {
          var i, j, len, src;
          for (j = 1, len = arguments.length; j < len; j++) {
            src = arguments[j];
            for (i in src) {
              dest[i] = src[i];
            }
          }
          return dest;
        }
        var create$2 = Object.create || /* @__PURE__ */ (function() {
          function F() {
          }
          return function(proto) {
            F.prototype = proto;
            return new F();
          };
        })();
        function bind(fn, obj) {
          var slice = Array.prototype.slice;
          if (fn.bind) {
            return fn.bind.apply(fn, slice.call(arguments, 1));
          }
          var args = slice.call(arguments, 2);
          return function() {
            return fn.apply(obj, args.length ? args.concat(slice.call(arguments)) : arguments);
          };
        }
        var lastId = 0;
        function stamp(obj) {
          if (!("_leaflet_id" in obj)) {
            obj["_leaflet_id"] = ++lastId;
          }
          return obj._leaflet_id;
        }
        function throttle(fn, time, context) {
          var lock, args, wrapperFn, later;
          later = function() {
            lock = false;
            if (args) {
              wrapperFn.apply(context, args);
              args = false;
            }
          };
          wrapperFn = function() {
            if (lock) {
              args = arguments;
            } else {
              fn.apply(context, arguments);
              setTimeout(later, time);
              lock = true;
            }
          };
          return wrapperFn;
        }
        function wrapNum(x, range, includeMax) {
          var max = range[1], min = range[0], d = max - min;
          return x === max && includeMax ? x : ((x - min) % d + d) % d + min;
        }
        function falseFn() {
          return false;
        }
        function formatNum(num, precision) {
          if (precision === false) {
            return num;
          }
          var pow = Math.pow(10, precision === void 0 ? 6 : precision);
          return Math.round(num * pow) / pow;
        }
        function trim(str) {
          return str.trim ? str.trim() : str.replace(/^\s+|\s+$/g, "");
        }
        function splitWords(str) {
          return trim(str).split(/\s+/);
        }
        function setOptions(obj, options) {
          if (!Object.prototype.hasOwnProperty.call(obj, "options")) {
            obj.options = obj.options ? create$2(obj.options) : {};
          }
          for (var i in options) {
            obj.options[i] = options[i];
          }
          return obj.options;
        }
        function getParamString(obj, existingUrl, uppercase) {
          var params = [];
          for (var i in obj) {
            params.push(encodeURIComponent(uppercase ? i.toUpperCase() : i) + "=" + encodeURIComponent(obj[i]));
          }
          return (!existingUrl || existingUrl.indexOf("?") === -1 ? "?" : "&") + params.join("&");
        }
        var templateRe = /\{ *([\w_ -]+) *\}/g;
        function template(str, data) {
          return str.replace(templateRe, function(str2, key) {
            var value = data[key];
            if (value === void 0) {
              throw new Error("No value provided for variable " + str2);
            } else if (typeof value === "function") {
              value = value(data);
            }
            return value;
          });
        }
        var isArray = Array.isArray || function(obj) {
          return Object.prototype.toString.call(obj) === "[object Array]";
        };
        function indexOf(array, el) {
          for (var i = 0; i < array.length; i++) {
            if (array[i] === el) {
              return i;
            }
          }
          return -1;
        }
        var emptyImageUrl = "data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=";
        function getPrefixed(name) {
          return window["webkit" + name] || window["moz" + name] || window["ms" + name];
        }
        var lastTime = 0;
        function timeoutDefer(fn) {
          var time = +/* @__PURE__ */ new Date(), timeToCall = Math.max(0, 16 - (time - lastTime));
          lastTime = time + timeToCall;
          return window.setTimeout(fn, timeToCall);
        }
        var requestFn = window.requestAnimationFrame || getPrefixed("RequestAnimationFrame") || timeoutDefer;
        var cancelFn = window.cancelAnimationFrame || getPrefixed("CancelAnimationFrame") || getPrefixed("CancelRequestAnimationFrame") || function(id) {
          window.clearTimeout(id);
        };
        function requestAnimFrame(fn, context, immediate) {
          if (immediate && requestFn === timeoutDefer) {
            fn.call(context);
          } else {
            return requestFn.call(window, bind(fn, context));
          }
        }
        function cancelAnimFrame(id) {
          if (id) {
            cancelFn.call(window, id);
          }
        }
        var Util = {
          __proto__: null,
          extend,
          create: create$2,
          bind,
          get lastId() {
            return lastId;
          },
          stamp,
          throttle,
          wrapNum,
          falseFn,
          formatNum,
          trim,
          splitWords,
          setOptions,
          getParamString,
          template,
          isArray,
          indexOf,
          emptyImageUrl,
          requestFn,
          cancelFn,
          requestAnimFrame,
          cancelAnimFrame
        };
        function Class() {
        }
        Class.extend = function(props) {
          var NewClass = function() {
            setOptions(this);
            if (this.initialize) {
              this.initialize.apply(this, arguments);
            }
            this.callInitHooks();
          };
          var parentProto = NewClass.__super__ = this.prototype;
          var proto = create$2(parentProto);
          proto.constructor = NewClass;
          NewClass.prototype = proto;
          for (var i in this) {
            if (Object.prototype.hasOwnProperty.call(this, i) && i !== "prototype" && i !== "__super__") {
              NewClass[i] = this[i];
            }
          }
          if (props.statics) {
            extend(NewClass, props.statics);
          }
          if (props.includes) {
            checkDeprecatedMixinEvents(props.includes);
            extend.apply(null, [proto].concat(props.includes));
          }
          extend(proto, props);
          delete proto.statics;
          delete proto.includes;
          if (proto.options) {
            proto.options = parentProto.options ? create$2(parentProto.options) : {};
            extend(proto.options, props.options);
          }
          proto._initHooks = [];
          proto.callInitHooks = function() {
            if (this._initHooksCalled) {
              return;
            }
            if (parentProto.callInitHooks) {
              parentProto.callInitHooks.call(this);
            }
            this._initHooksCalled = true;
            for (var i2 = 0, len = proto._initHooks.length; i2 < len; i2++) {
              proto._initHooks[i2].call(this);
            }
          };
          return NewClass;
        };
        Class.include = function(props) {
          var parentOptions = this.prototype.options;
          extend(this.prototype, props);
          if (props.options) {
            this.prototype.options = parentOptions;
            this.mergeOptions(props.options);
          }
          return this;
        };
        Class.mergeOptions = function(options) {
          extend(this.prototype.options, options);
          return this;
        };
        Class.addInitHook = function(fn) {
          var args = Array.prototype.slice.call(arguments, 1);
          var init = typeof fn === "function" ? fn : function() {
            this[fn].apply(this, args);
          };
          this.prototype._initHooks = this.prototype._initHooks || [];
          this.prototype._initHooks.push(init);
          return this;
        };
        function checkDeprecatedMixinEvents(includes) {
          if (typeof L === "undefined" || !L || !L.Mixin) {
            return;
          }
          includes = isArray(includes) ? includes : [includes];
          for (var i = 0; i < includes.length; i++) {
            if (includes[i] === L.Mixin.Events) {
              console.warn("Deprecated include of L.Mixin.Events: this property will be removed in future releases, please inherit from L.Evented instead.", new Error().stack);
            }
          }
        }
        var Events = {
          /* @method on(type: String, fn: Function, context?: Object): this
           * Adds a listener function (`fn`) to a particular event type of the object. You can optionally specify the context of the listener (object the this keyword will point to). You can also pass several space-separated types (e.g. `'click dblclick'`).
           *
           * @alternative
           * @method on(eventMap: Object): this
           * Adds a set of type/listener pairs, e.g. `{click: onClick, mousemove: onMouseMove}`
           */
          on: function(types, fn, context) {
            if (typeof types === "object") {
              for (var type in types) {
                this._on(type, types[type], fn);
              }
            } else {
              types = splitWords(types);
              for (var i = 0, len = types.length; i < len; i++) {
                this._on(types[i], fn, context);
              }
            }
            return this;
          },
          /* @method off(type: String, fn?: Function, context?: Object): this
           * Removes a previously added listener function. If no function is specified, it will remove all the listeners of that particular event from the object. Note that if you passed a custom context to `on`, you must pass the same context to `off` in order to remove the listener.
           *
           * @alternative
           * @method off(eventMap: Object): this
           * Removes a set of type/listener pairs.
           *
           * @alternative
           * @method off: this
           * Removes all listeners to all events on the object. This includes implicitly attached events.
           */
          off: function(types, fn, context) {
            if (!arguments.length) {
              delete this._events;
            } else if (typeof types === "object") {
              for (var type in types) {
                this._off(type, types[type], fn);
              }
            } else {
              types = splitWords(types);
              var removeAll = arguments.length === 1;
              for (var i = 0, len = types.length; i < len; i++) {
                if (removeAll) {
                  this._off(types[i]);
                } else {
                  this._off(types[i], fn, context);
                }
              }
            }
            return this;
          },
          // attach listener (without syntactic sugar now)
          _on: function(type, fn, context, _once) {
            if (typeof fn !== "function") {
              console.warn("wrong listener type: " + typeof fn);
              return;
            }
            if (this._listens(type, fn, context) !== false) {
              return;
            }
            if (context === this) {
              context = void 0;
            }
            var newListener = { fn, ctx: context };
            if (_once) {
              newListener.once = true;
            }
            this._events = this._events || {};
            this._events[type] = this._events[type] || [];
            this._events[type].push(newListener);
          },
          _off: function(type, fn, context) {
            var listeners, i, len;
            if (!this._events) {
              return;
            }
            listeners = this._events[type];
            if (!listeners) {
              return;
            }
            if (arguments.length === 1) {
              if (this._firingCount) {
                for (i = 0, len = listeners.length; i < len; i++) {
                  listeners[i].fn = falseFn;
                }
              }
              delete this._events[type];
              return;
            }
            if (typeof fn !== "function") {
              console.warn("wrong listener type: " + typeof fn);
              return;
            }
            var index2 = this._listens(type, fn, context);
            if (index2 !== false) {
              var listener = listeners[index2];
              if (this._firingCount) {
                listener.fn = falseFn;
                this._events[type] = listeners = listeners.slice();
              }
              listeners.splice(index2, 1);
            }
          },
          // @method fire(type: String, data?: Object, propagate?: Boolean): this
          // Fires an event of the specified type. You can optionally provide a data
          // object — the first argument of the listener function will contain its
          // properties. The event can optionally be propagated to event parents.
          fire: function(type, data, propagate) {
            if (!this.listens(type, propagate)) {
              return this;
            }
            var event = extend({}, data, {
              type,
              target: this,
              sourceTarget: data && data.sourceTarget || this
            });
            if (this._events) {
              var listeners = this._events[type];
              if (listeners) {
                this._firingCount = this._firingCount + 1 || 1;
                for (var i = 0, len = listeners.length; i < len; i++) {
                  var l = listeners[i];
                  var fn = l.fn;
                  if (l.once) {
                    this.off(type, fn, l.ctx);
                  }
                  fn.call(l.ctx || this, event);
                }
                this._firingCount--;
              }
            }
            if (propagate) {
              this._propagateEvent(event);
            }
            return this;
          },
          // @method listens(type: String, propagate?: Boolean): Boolean
          // @method listens(type: String, fn: Function, context?: Object, propagate?: Boolean): Boolean
          // Returns `true` if a particular event type has any listeners attached to it.
          // The verification can optionally be propagated, it will return `true` if parents have the listener attached to it.
          listens: function(type, fn, context, propagate) {
            if (typeof type !== "string") {
              console.warn('"string" type argument expected');
            }
            var _fn = fn;
            if (typeof fn !== "function") {
              propagate = !!fn;
              _fn = void 0;
              context = void 0;
            }
            var listeners = this._events && this._events[type];
            if (listeners && listeners.length) {
              if (this._listens(type, _fn, context) !== false) {
                return true;
              }
            }
            if (propagate) {
              for (var id in this._eventParents) {
                if (this._eventParents[id].listens(type, fn, context, propagate)) {
                  return true;
                }
              }
            }
            return false;
          },
          // returns the index (number) or false
          _listens: function(type, fn, context) {
            if (!this._events) {
              return false;
            }
            var listeners = this._events[type] || [];
            if (!fn) {
              return !!listeners.length;
            }
            if (context === this) {
              context = void 0;
            }
            for (var i = 0, len = listeners.length; i < len; i++) {
              if (listeners[i].fn === fn && listeners[i].ctx === context) {
                return i;
              }
            }
            return false;
          },
          // @method once(…): this
          // Behaves as [`on(…)`](#evented-on), except the listener will only get fired once and then removed.
          once: function(types, fn, context) {
            if (typeof types === "object") {
              for (var type in types) {
                this._on(type, types[type], fn, true);
              }
            } else {
              types = splitWords(types);
              for (var i = 0, len = types.length; i < len; i++) {
                this._on(types[i], fn, context, true);
              }
            }
            return this;
          },
          // @method addEventParent(obj: Evented): this
          // Adds an event parent - an `Evented` that will receive propagated events
          addEventParent: function(obj) {
            this._eventParents = this._eventParents || {};
            this._eventParents[stamp(obj)] = obj;
            return this;
          },
          // @method removeEventParent(obj: Evented): this
          // Removes an event parent, so it will stop receiving propagated events
          removeEventParent: function(obj) {
            if (this._eventParents) {
              delete this._eventParents[stamp(obj)];
            }
            return this;
          },
          _propagateEvent: function(e) {
            for (var id in this._eventParents) {
              this._eventParents[id].fire(e.type, extend({
                layer: e.target,
                propagatedFrom: e.target
              }, e), true);
            }
          }
        };
        Events.addEventListener = Events.on;
        Events.removeEventListener = Events.clearAllEventListeners = Events.off;
        Events.addOneTimeEventListener = Events.once;
        Events.fireEvent = Events.fire;
        Events.hasEventListeners = Events.listens;
        var Evented = Class.extend(Events);
        function Point(x, y, round) {
          this.x = round ? Math.round(x) : x;
          this.y = round ? Math.round(y) : y;
        }
        var trunc = Math.trunc || function(v) {
          return v > 0 ? Math.floor(v) : Math.ceil(v);
        };
        Point.prototype = {
          // @method clone(): Point
          // Returns a copy of the current point.
          clone: function() {
            return new Point(this.x, this.y);
          },
          // @method add(otherPoint: Point): Point
          // Returns the result of addition of the current and the given points.
          add: function(point) {
            return this.clone()._add(toPoint(point));
          },
          _add: function(point) {
            this.x += point.x;
            this.y += point.y;
            return this;
          },
          // @method subtract(otherPoint: Point): Point
          // Returns the result of subtraction of the given point from the current.
          subtract: function(point) {
            return this.clone()._subtract(toPoint(point));
          },
          _subtract: function(point) {
            this.x -= point.x;
            this.y -= point.y;
            return this;
          },
          // @method divideBy(num: Number): Point
          // Returns the result of division of the current point by the given number.
          divideBy: function(num) {
            return this.clone()._divideBy(num);
          },
          _divideBy: function(num) {
            this.x /= num;
            this.y /= num;
            return this;
          },
          // @method multiplyBy(num: Number): Point
          // Returns the result of multiplication of the current point by the given number.
          multiplyBy: function(num) {
            return this.clone()._multiplyBy(num);
          },
          _multiplyBy: function(num) {
            this.x *= num;
            this.y *= num;
            return this;
          },
          // @method scaleBy(scale: Point): Point
          // Multiply each coordinate of the current point by each coordinate of
          // `scale`. In linear algebra terms, multiply the point by the
          // [scaling matrix](https://en.wikipedia.org/wiki/Scaling_%28geometry%29#Matrix_representation)
          // defined by `scale`.
          scaleBy: function(point) {
            return new Point(this.x * point.x, this.y * point.y);
          },
          // @method unscaleBy(scale: Point): Point
          // Inverse of `scaleBy`. Divide each coordinate of the current point by
          // each coordinate of `scale`.
          unscaleBy: function(point) {
            return new Point(this.x / point.x, this.y / point.y);
          },
          // @method round(): Point
          // Returns a copy of the current point with rounded coordinates.
          round: function() {
            return this.clone()._round();
          },
          _round: function() {
            this.x = Math.round(this.x);
            this.y = Math.round(this.y);
            return this;
          },
          // @method floor(): Point
          // Returns a copy of the current point with floored coordinates (rounded down).
          floor: function() {
            return this.clone()._floor();
          },
          _floor: function() {
            this.x = Math.floor(this.x);
            this.y = Math.floor(this.y);
            return this;
          },
          // @method ceil(): Point
          // Returns a copy of the current point with ceiled coordinates (rounded up).
          ceil: function() {
            return this.clone()._ceil();
          },
          _ceil: function() {
            this.x = Math.ceil(this.x);
            this.y = Math.ceil(this.y);
            return this;
          },
          // @method trunc(): Point
          // Returns a copy of the current point with truncated coordinates (rounded towards zero).
          trunc: function() {
            return this.clone()._trunc();
          },
          _trunc: function() {
            this.x = trunc(this.x);
            this.y = trunc(this.y);
            return this;
          },
          // @method distanceTo(otherPoint: Point): Number
          // Returns the cartesian distance between the current and the given points.
          distanceTo: function(point) {
            point = toPoint(point);
            var x = point.x - this.x, y = point.y - this.y;
            return Math.sqrt(x * x + y * y);
          },
          // @method equals(otherPoint: Point): Boolean
          // Returns `true` if the given point has the same coordinates.
          equals: function(point) {
            point = toPoint(point);
            return point.x === this.x && point.y === this.y;
          },
          // @method contains(otherPoint: Point): Boolean
          // Returns `true` if both coordinates of the given point are less than the corresponding current point coordinates (in absolute values).
          contains: function(point) {
            point = toPoint(point);
            return Math.abs(point.x) <= Math.abs(this.x) && Math.abs(point.y) <= Math.abs(this.y);
          },
          // @method toString(): String
          // Returns a string representation of the point for debugging purposes.
          toString: function() {
            return "Point(" + formatNum(this.x) + ", " + formatNum(this.y) + ")";
          }
        };
        function toPoint(x, y, round) {
          if (x instanceof Point) {
            return x;
          }
          if (isArray(x)) {
            return new Point(x[0], x[1]);
          }
          if (x === void 0 || x === null) {
            return x;
          }
          if (typeof x === "object" && "x" in x && "y" in x) {
            return new Point(x.x, x.y);
          }
          return new Point(x, y, round);
        }
        function Bounds(a, b) {
          if (!a) {
            return;
          }
          var points = b ? [a, b] : a;
          for (var i = 0, len = points.length; i < len; i++) {
            this.extend(points[i]);
          }
        }
        Bounds.prototype = {
          // @method extend(point: Point): this
          // Extends the bounds to contain the given point.
          // @alternative
          // @method extend(otherBounds: Bounds): this
          // Extend the bounds to contain the given bounds
          extend: function(obj) {
            var min2, max2;
            if (!obj) {
              return this;
            }
            if (obj instanceof Point || typeof obj[0] === "number" || "x" in obj) {
              min2 = max2 = toPoint(obj);
            } else {
              obj = toBounds(obj);
              min2 = obj.min;
              max2 = obj.max;
              if (!min2 || !max2) {
                return this;
              }
            }
            if (!this.min && !this.max) {
              this.min = min2.clone();
              this.max = max2.clone();
            } else {
              this.min.x = Math.min(min2.x, this.min.x);
              this.max.x = Math.max(max2.x, this.max.x);
              this.min.y = Math.min(min2.y, this.min.y);
              this.max.y = Math.max(max2.y, this.max.y);
            }
            return this;
          },
          // @method getCenter(round?: Boolean): Point
          // Returns the center point of the bounds.
          getCenter: function(round) {
            return toPoint(
              (this.min.x + this.max.x) / 2,
              (this.min.y + this.max.y) / 2,
              round
            );
          },
          // @method getBottomLeft(): Point
          // Returns the bottom-left point of the bounds.
          getBottomLeft: function() {
            return toPoint(this.min.x, this.max.y);
          },
          // @method getTopRight(): Point
          // Returns the top-right point of the bounds.
          getTopRight: function() {
            return toPoint(this.max.x, this.min.y);
          },
          // @method getTopLeft(): Point
          // Returns the top-left point of the bounds (i.e. [`this.min`](#bounds-min)).
          getTopLeft: function() {
            return this.min;
          },
          // @method getBottomRight(): Point
          // Returns the bottom-right point of the bounds (i.e. [`this.max`](#bounds-max)).
          getBottomRight: function() {
            return this.max;
          },
          // @method getSize(): Point
          // Returns the size of the given bounds
          getSize: function() {
            return this.max.subtract(this.min);
          },
          // @method contains(otherBounds: Bounds): Boolean
          // Returns `true` if the rectangle contains the given one.
          // @alternative
          // @method contains(point: Point): Boolean
          // Returns `true` if the rectangle contains the given point.
          contains: function(obj) {
            var min, max;
            if (typeof obj[0] === "number" || obj instanceof Point) {
              obj = toPoint(obj);
            } else {
              obj = toBounds(obj);
            }
            if (obj instanceof Bounds) {
              min = obj.min;
              max = obj.max;
            } else {
              min = max = obj;
            }
            return min.x >= this.min.x && max.x <= this.max.x && min.y >= this.min.y && max.y <= this.max.y;
          },
          // @method intersects(otherBounds: Bounds): Boolean
          // Returns `true` if the rectangle intersects the given bounds. Two bounds
          // intersect if they have at least one point in common.
          intersects: function(bounds) {
            bounds = toBounds(bounds);
            var min = this.min, max = this.max, min2 = bounds.min, max2 = bounds.max, xIntersects = max2.x >= min.x && min2.x <= max.x, yIntersects = max2.y >= min.y && min2.y <= max.y;
            return xIntersects && yIntersects;
          },
          // @method overlaps(otherBounds: Bounds): Boolean
          // Returns `true` if the rectangle overlaps the given bounds. Two bounds
          // overlap if their intersection is an area.
          overlaps: function(bounds) {
            bounds = toBounds(bounds);
            var min = this.min, max = this.max, min2 = bounds.min, max2 = bounds.max, xOverlaps = max2.x > min.x && min2.x < max.x, yOverlaps = max2.y > min.y && min2.y < max.y;
            return xOverlaps && yOverlaps;
          },
          // @method isValid(): Boolean
          // Returns `true` if the bounds are properly initialized.
          isValid: function() {
            return !!(this.min && this.max);
          },
          // @method pad(bufferRatio: Number): Bounds
          // Returns bounds created by extending or retracting the current bounds by a given ratio in each direction.
          // For example, a ratio of 0.5 extends the bounds by 50% in each direction.
          // Negative values will retract the bounds.
          pad: function(bufferRatio) {
            var min = this.min, max = this.max, heightBuffer = Math.abs(min.x - max.x) * bufferRatio, widthBuffer = Math.abs(min.y - max.y) * bufferRatio;
            return toBounds(
              toPoint(min.x - heightBuffer, min.y - widthBuffer),
              toPoint(max.x + heightBuffer, max.y + widthBuffer)
            );
          },
          // @method equals(otherBounds: Bounds): Boolean
          // Returns `true` if the rectangle is equivalent to the given bounds.
          equals: function(bounds) {
            if (!bounds) {
              return false;
            }
            bounds = toBounds(bounds);
            return this.min.equals(bounds.getTopLeft()) && this.max.equals(bounds.getBottomRight());
          }
        };
        function toBounds(a, b) {
          if (!a || a instanceof Bounds) {
            return a;
          }
          return new Bounds(a, b);
        }
        function LatLngBounds(corner1, corner2) {
          if (!corner1) {
            return;
          }
          var latlngs = corner2 ? [corner1, corner2] : corner1;
          for (var i = 0, len = latlngs.length; i < len; i++) {
            this.extend(latlngs[i]);
          }
        }
        LatLngBounds.prototype = {
          // @method extend(latlng: LatLng): this
          // Extend the bounds to contain the given point
          // @alternative
          // @method extend(otherBounds: LatLngBounds): this
          // Extend the bounds to contain the given bounds
          extend: function(obj) {
            var sw = this._southWest, ne = this._northEast, sw2, ne2;
            if (obj instanceof LatLng) {
              sw2 = obj;
              ne2 = obj;
            } else if (obj instanceof LatLngBounds) {
              sw2 = obj._southWest;
              ne2 = obj._northEast;
              if (!sw2 || !ne2) {
                return this;
              }
            } else {
              return obj ? this.extend(toLatLng(obj) || toLatLngBounds(obj)) : this;
            }
            if (!sw && !ne) {
              this._southWest = new LatLng(sw2.lat, sw2.lng);
              this._northEast = new LatLng(ne2.lat, ne2.lng);
            } else {
              sw.lat = Math.min(sw2.lat, sw.lat);
              sw.lng = Math.min(sw2.lng, sw.lng);
              ne.lat = Math.max(ne2.lat, ne.lat);
              ne.lng = Math.max(ne2.lng, ne.lng);
            }
            return this;
          },
          // @method pad(bufferRatio: Number): LatLngBounds
          // Returns bounds created by extending or retracting the current bounds by a given ratio in each direction.
          // For example, a ratio of 0.5 extends the bounds by 50% in each direction.
          // Negative values will retract the bounds.
          pad: function(bufferRatio) {
            var sw = this._southWest, ne = this._northEast, heightBuffer = Math.abs(sw.lat - ne.lat) * bufferRatio, widthBuffer = Math.abs(sw.lng - ne.lng) * bufferRatio;
            return new LatLngBounds(
              new LatLng(sw.lat - heightBuffer, sw.lng - widthBuffer),
              new LatLng(ne.lat + heightBuffer, ne.lng + widthBuffer)
            );
          },
          // @method getCenter(): LatLng
          // Returns the center point of the bounds.
          getCenter: function() {
            return new LatLng(
              (this._southWest.lat + this._northEast.lat) / 2,
              (this._southWest.lng + this._northEast.lng) / 2
            );
          },
          // @method getSouthWest(): LatLng
          // Returns the south-west point of the bounds.
          getSouthWest: function() {
            return this._southWest;
          },
          // @method getNorthEast(): LatLng
          // Returns the north-east point of the bounds.
          getNorthEast: function() {
            return this._northEast;
          },
          // @method getNorthWest(): LatLng
          // Returns the north-west point of the bounds.
          getNorthWest: function() {
            return new LatLng(this.getNorth(), this.getWest());
          },
          // @method getSouthEast(): LatLng
          // Returns the south-east point of the bounds.
          getSouthEast: function() {
            return new LatLng(this.getSouth(), this.getEast());
          },
          // @method getWest(): Number
          // Returns the west longitude of the bounds
          getWest: function() {
            return this._southWest.lng;
          },
          // @method getSouth(): Number
          // Returns the south latitude of the bounds
          getSouth: function() {
            return this._southWest.lat;
          },
          // @method getEast(): Number
          // Returns the east longitude of the bounds
          getEast: function() {
            return this._northEast.lng;
          },
          // @method getNorth(): Number
          // Returns the north latitude of the bounds
          getNorth: function() {
            return this._northEast.lat;
          },
          // @method contains(otherBounds: LatLngBounds): Boolean
          // Returns `true` if the rectangle contains the given one.
          // @alternative
          // @method contains (latlng: LatLng): Boolean
          // Returns `true` if the rectangle contains the given point.
          contains: function(obj) {
            if (typeof obj[0] === "number" || obj instanceof LatLng || "lat" in obj) {
              obj = toLatLng(obj);
            } else {
              obj = toLatLngBounds(obj);
            }
            var sw = this._southWest, ne = this._northEast, sw2, ne2;
            if (obj instanceof LatLngBounds) {
              sw2 = obj.getSouthWest();
              ne2 = obj.getNorthEast();
            } else {
              sw2 = ne2 = obj;
            }
            return sw2.lat >= sw.lat && ne2.lat <= ne.lat && sw2.lng >= sw.lng && ne2.lng <= ne.lng;
          },
          // @method intersects(otherBounds: LatLngBounds): Boolean
          // Returns `true` if the rectangle intersects the given bounds. Two bounds intersect if they have at least one point in common.
          intersects: function(bounds) {
            bounds = toLatLngBounds(bounds);
            var sw = this._southWest, ne = this._northEast, sw2 = bounds.getSouthWest(), ne2 = bounds.getNorthEast(), latIntersects = ne2.lat >= sw.lat && sw2.lat <= ne.lat, lngIntersects = ne2.lng >= sw.lng && sw2.lng <= ne.lng;
            return latIntersects && lngIntersects;
          },
          // @method overlaps(otherBounds: LatLngBounds): Boolean
          // Returns `true` if the rectangle overlaps the given bounds. Two bounds overlap if their intersection is an area.
          overlaps: function(bounds) {
            bounds = toLatLngBounds(bounds);
            var sw = this._southWest, ne = this._northEast, sw2 = bounds.getSouthWest(), ne2 = bounds.getNorthEast(), latOverlaps = ne2.lat > sw.lat && sw2.lat < ne.lat, lngOverlaps = ne2.lng > sw.lng && sw2.lng < ne.lng;
            return latOverlaps && lngOverlaps;
          },
          // @method toBBoxString(): String
          // Returns a string with bounding box coordinates in a 'southwest_lng,southwest_lat,northeast_lng,northeast_lat' format. Useful for sending requests to web services that return geo data.
          toBBoxString: function() {
            return [this.getWest(), this.getSouth(), this.getEast(), this.getNorth()].join(",");
          },
          // @method equals(otherBounds: LatLngBounds, maxMargin?: Number): Boolean
          // Returns `true` if the rectangle is equivalent (within a small margin of error) to the given bounds. The margin of error can be overridden by setting `maxMargin` to a small number.
          equals: function(bounds, maxMargin) {
            if (!bounds) {
              return false;
            }
            bounds = toLatLngBounds(bounds);
            return this._southWest.equals(bounds.getSouthWest(), maxMargin) && this._northEast.equals(bounds.getNorthEast(), maxMargin);
          },
          // @method isValid(): Boolean
          // Returns `true` if the bounds are properly initialized.
          isValid: function() {
            return !!(this._southWest && this._northEast);
          }
        };
        function toLatLngBounds(a, b) {
          if (a instanceof LatLngBounds) {
            return a;
          }
          return new LatLngBounds(a, b);
        }
        function LatLng(lat, lng, alt) {
          if (isNaN(lat) || isNaN(lng)) {
            throw new Error("Invalid LatLng object: (" + lat + ", " + lng + ")");
          }
          this.lat = +lat;
          this.lng = +lng;
          if (alt !== void 0) {
            this.alt = +alt;
          }
        }
        LatLng.prototype = {
          // @method equals(otherLatLng: LatLng, maxMargin?: Number): Boolean
          // Returns `true` if the given `LatLng` point is at the same position (within a small margin of error). The margin of error can be overridden by setting `maxMargin` to a small number.
          equals: function(obj, maxMargin) {
            if (!obj) {
              return false;
            }
            obj = toLatLng(obj);
            var margin = Math.max(
              Math.abs(this.lat - obj.lat),
              Math.abs(this.lng - obj.lng)
            );
            return margin <= (maxMargin === void 0 ? 1e-9 : maxMargin);
          },
          // @method toString(): String
          // Returns a string representation of the point (for debugging purposes).
          toString: function(precision) {
            return "LatLng(" + formatNum(this.lat, precision) + ", " + formatNum(this.lng, precision) + ")";
          },
          // @method distanceTo(otherLatLng: LatLng): Number
          // Returns the distance (in meters) to the given `LatLng` calculated using the [Spherical Law of Cosines](https://en.wikipedia.org/wiki/Spherical_law_of_cosines).
          distanceTo: function(other) {
            return Earth.distance(this, toLatLng(other));
          },
          // @method wrap(): LatLng
          // Returns a new `LatLng` object with the longitude wrapped so it's always between -180 and +180 degrees.
          wrap: function() {
            return Earth.wrapLatLng(this);
          },
          // @method toBounds(sizeInMeters: Number): LatLngBounds
          // Returns a new `LatLngBounds` object in which each boundary is `sizeInMeters/2` meters apart from the `LatLng`.
          toBounds: function(sizeInMeters) {
            var latAccuracy = 180 * sizeInMeters / 40075017, lngAccuracy = latAccuracy / Math.cos(Math.PI / 180 * this.lat);
            return toLatLngBounds(
              [this.lat - latAccuracy, this.lng - lngAccuracy],
              [this.lat + latAccuracy, this.lng + lngAccuracy]
            );
          },
          clone: function() {
            return new LatLng(this.lat, this.lng, this.alt);
          }
        };
        function toLatLng(a, b, c) {
          if (a instanceof LatLng) {
            return a;
          }
          if (isArray(a) && typeof a[0] !== "object") {
            if (a.length === 3) {
              return new LatLng(a[0], a[1], a[2]);
            }
            if (a.length === 2) {
              return new LatLng(a[0], a[1]);
            }
            return null;
          }
          if (a === void 0 || a === null) {
            return a;
          }
          if (typeof a === "object" && "lat" in a) {
            return new LatLng(a.lat, "lng" in a ? a.lng : a.lon, a.alt);
          }
          if (b === void 0) {
            return null;
          }
          return new LatLng(a, b, c);
        }
        var CRS = {
          // @method latLngToPoint(latlng: LatLng, zoom: Number): Point
          // Projects geographical coordinates into pixel coordinates for a given zoom.
          latLngToPoint: function(latlng, zoom2) {
            var projectedPoint = this.projection.project(latlng), scale2 = this.scale(zoom2);
            return this.transformation._transform(projectedPoint, scale2);
          },
          // @method pointToLatLng(point: Point, zoom: Number): LatLng
          // The inverse of `latLngToPoint`. Projects pixel coordinates on a given
          // zoom into geographical coordinates.
          pointToLatLng: function(point, zoom2) {
            var scale2 = this.scale(zoom2), untransformedPoint = this.transformation.untransform(point, scale2);
            return this.projection.unproject(untransformedPoint);
          },
          // @method project(latlng: LatLng): Point
          // Projects geographical coordinates into coordinates in units accepted for
          // this CRS (e.g. meters for EPSG:3857, for passing it to WMS services).
          project: function(latlng) {
            return this.projection.project(latlng);
          },
          // @method unproject(point: Point): LatLng
          // Given a projected coordinate returns the corresponding LatLng.
          // The inverse of `project`.
          unproject: function(point) {
            return this.projection.unproject(point);
          },
          // @method scale(zoom: Number): Number
          // Returns the scale used when transforming projected coordinates into
          // pixel coordinates for a particular zoom. For example, it returns
          // `256 * 2^zoom` for Mercator-based CRS.
          scale: function(zoom2) {
            return 256 * Math.pow(2, zoom2);
          },
          // @method zoom(scale: Number): Number
          // Inverse of `scale()`, returns the zoom level corresponding to a scale
          // factor of `scale`.
          zoom: function(scale2) {
            return Math.log(scale2 / 256) / Math.LN2;
          },
          // @method getProjectedBounds(zoom: Number): Bounds
          // Returns the projection's bounds scaled and transformed for the provided `zoom`.
          getProjectedBounds: function(zoom2) {
            if (this.infinite) {
              return null;
            }
            var b = this.projection.bounds, s = this.scale(zoom2), min = this.transformation.transform(b.min, s), max = this.transformation.transform(b.max, s);
            return new Bounds(min, max);
          },
          // @method distance(latlng1: LatLng, latlng2: LatLng): Number
          // Returns the distance between two geographical coordinates.
          // @property code: String
          // Standard code name of the CRS passed into WMS services (e.g. `'EPSG:3857'`)
          //
          // @property wrapLng: Number[]
          // An array of two numbers defining whether the longitude (horizontal) coordinate
          // axis wraps around a given range and how. Defaults to `[-180, 180]` in most
          // geographical CRSs. If `undefined`, the longitude axis does not wrap around.
          //
          // @property wrapLat: Number[]
          // Like `wrapLng`, but for the latitude (vertical) axis.
          // wrapLng: [min, max],
          // wrapLat: [min, max],
          // @property infinite: Boolean
          // If true, the coordinate space will be unbounded (infinite in both axes)
          infinite: false,
          // @method wrapLatLng(latlng: LatLng): LatLng
          // Returns a `LatLng` where lat and lng has been wrapped according to the
          // CRS's `wrapLat` and `wrapLng` properties, if they are outside the CRS's bounds.
          wrapLatLng: function(latlng) {
            var lng = this.wrapLng ? wrapNum(latlng.lng, this.wrapLng, true) : latlng.lng, lat = this.wrapLat ? wrapNum(latlng.lat, this.wrapLat, true) : latlng.lat, alt = latlng.alt;
            return new LatLng(lat, lng, alt);
          },
          // @method wrapLatLngBounds(bounds: LatLngBounds): LatLngBounds
          // Returns a `LatLngBounds` with the same size as the given one, ensuring
          // that its center is within the CRS's bounds.
          // Only accepts actual `L.LatLngBounds` instances, not arrays.
          wrapLatLngBounds: function(bounds) {
            var center = bounds.getCenter(), newCenter = this.wrapLatLng(center), latShift = center.lat - newCenter.lat, lngShift = center.lng - newCenter.lng;
            if (latShift === 0 && lngShift === 0) {
              return bounds;
            }
            var sw = bounds.getSouthWest(), ne = bounds.getNorthEast(), newSw = new LatLng(sw.lat - latShift, sw.lng - lngShift), newNe = new LatLng(ne.lat - latShift, ne.lng - lngShift);
            return new LatLngBounds(newSw, newNe);
          }
        };
        var Earth = extend({}, CRS, {
          wrapLng: [-180, 180],
          // Mean Earth Radius, as recommended for use by
          // the International Union of Geodesy and Geophysics,
          // see https://rosettacode.org/wiki/Haversine_formula
          R: 6371e3,
          // distance between two geographical points using spherical law of cosines approximation
          distance: function(latlng1, latlng2) {
            var rad = Math.PI / 180, lat1 = latlng1.lat * rad, lat2 = latlng2.lat * rad, sinDLat = Math.sin((latlng2.lat - latlng1.lat) * rad / 2), sinDLon = Math.sin((latlng2.lng - latlng1.lng) * rad / 2), a = sinDLat * sinDLat + Math.cos(lat1) * Math.cos(lat2) * sinDLon * sinDLon, c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
            return this.R * c;
          }
        });
        var earthRadius = 6378137;
        var SphericalMercator = {
          R: earthRadius,
          MAX_LATITUDE: 85.0511287798,
          project: function(latlng) {
            var d = Math.PI / 180, max = this.MAX_LATITUDE, lat = Math.max(Math.min(max, latlng.lat), -max), sin = Math.sin(lat * d);
            return new Point(
              this.R * latlng.lng * d,
              this.R * Math.log((1 + sin) / (1 - sin)) / 2
            );
          },
          unproject: function(point) {
            var d = 180 / Math.PI;
            return new LatLng(
              (2 * Math.atan(Math.exp(point.y / this.R)) - Math.PI / 2) * d,
              point.x * d / this.R
            );
          },
          bounds: (function() {
            var d = earthRadius * Math.PI;
            return new Bounds([-d, -d], [d, d]);
          })()
        };
        function Transformation(a, b, c, d) {
          if (isArray(a)) {
            this._a = a[0];
            this._b = a[1];
            this._c = a[2];
            this._d = a[3];
            return;
          }
          this._a = a;
          this._b = b;
          this._c = c;
          this._d = d;
        }
        Transformation.prototype = {
          // @method transform(point: Point, scale?: Number): Point
          // Returns a transformed point, optionally multiplied by the given scale.
          // Only accepts actual `L.Point` instances, not arrays.
          transform: function(point, scale2) {
            return this._transform(point.clone(), scale2);
          },
          // destructive transform (faster)
          _transform: function(point, scale2) {
            scale2 = scale2 || 1;
            point.x = scale2 * (this._a * point.x + this._b);
            point.y = scale2 * (this._c * point.y + this._d);
            return point;
          },
          // @method untransform(point: Point, scale?: Number): Point
          // Returns the reverse transformation of the given point, optionally divided
          // by the given scale. Only accepts actual `L.Point` instances, not arrays.
          untransform: function(point, scale2) {
            scale2 = scale2 || 1;
            return new Point(
              (point.x / scale2 - this._b) / this._a,
              (point.y / scale2 - this._d) / this._c
            );
          }
        };
        function toTransformation(a, b, c, d) {
          return new Transformation(a, b, c, d);
        }
        var EPSG3857 = extend({}, Earth, {
          code: "EPSG:3857",
          projection: SphericalMercator,
          transformation: (function() {
            var scale2 = 0.5 / (Math.PI * SphericalMercator.R);
            return toTransformation(scale2, 0.5, -scale2, 0.5);
          })()
        });
        var EPSG900913 = extend({}, EPSG3857, {
          code: "EPSG:900913"
        });
        function svgCreate(name) {
          return document.createElementNS("http://www.w3.org/2000/svg", name);
        }
        function pointsToPath(rings, closed) {
          var str = "", i, j, len, len2, points, p;
          for (i = 0, len = rings.length; i < len; i++) {
            points = rings[i];
            for (j = 0, len2 = points.length; j < len2; j++) {
              p = points[j];
              str += (j ? "L" : "M") + p.x + " " + p.y;
            }
            str += closed ? Browser.svg ? "z" : "x" : "";
          }
          return str || "M0 0";
        }
        var style = document.documentElement.style;
        var ie = "ActiveXObject" in window;
        var ielt9 = ie && !document.addEventListener;
        var edge = "msLaunchUri" in navigator && !("documentMode" in document);
        var webkit = userAgentContains("webkit");
        var android = userAgentContains("android");
        var android23 = userAgentContains("android 2") || userAgentContains("android 3");
        var webkitVer = parseInt(/WebKit\/([0-9]+)|$/.exec(navigator.userAgent)[1], 10);
        var androidStock = android && userAgentContains("Google") && webkitVer < 537 && !("AudioNode" in window);
        var opera = !!window.opera;
        var chrome = !edge && userAgentContains("chrome");
        var gecko = userAgentContains("gecko") && !webkit && !opera && !ie;
        var safari = !chrome && userAgentContains("safari");
        var phantom = userAgentContains("phantom");
        var opera12 = "OTransition" in style;
        var win = navigator.platform.indexOf("Win") === 0;
        var ie3d = ie && "transition" in style;
        var webkit3d = "WebKitCSSMatrix" in window && "m11" in new window.WebKitCSSMatrix() && !android23;
        var gecko3d = "MozPerspective" in style;
        var any3d = !window.L_DISABLE_3D && (ie3d || webkit3d || gecko3d) && !opera12 && !phantom;
        var mobile = typeof orientation !== "undefined" || userAgentContains("mobile");
        var mobileWebkit = mobile && webkit;
        var mobileWebkit3d = mobile && webkit3d;
        var msPointer = !window.PointerEvent && window.MSPointerEvent;
        var pointer = !!(window.PointerEvent || msPointer);
        var touchNative = "ontouchstart" in window || !!window.TouchEvent;
        var touch = !window.L_NO_TOUCH && (touchNative || pointer);
        var mobileOpera = mobile && opera;
        var mobileGecko = mobile && gecko;
        var retina = (window.devicePixelRatio || window.screen.deviceXDPI / window.screen.logicalXDPI) > 1;
        var passiveEvents = (function() {
          var supportsPassiveOption = false;
          try {
            var opts = Object.defineProperty({}, "passive", {
              get: function() {
                supportsPassiveOption = true;
              }
            });
            window.addEventListener("testPassiveEventSupport", falseFn, opts);
            window.removeEventListener("testPassiveEventSupport", falseFn, opts);
          } catch (e) {
          }
          return supportsPassiveOption;
        })();
        var canvas$1 = (function() {
          return !!document.createElement("canvas").getContext;
        })();
        var svg$1 = !!(document.createElementNS && svgCreate("svg").createSVGRect);
        var inlineSvg = !!svg$1 && (function() {
          var div = document.createElement("div");
          div.innerHTML = "<svg/>";
          return (div.firstChild && div.firstChild.namespaceURI) === "http://www.w3.org/2000/svg";
        })();
        var vml = !svg$1 && (function() {
          try {
            var div = document.createElement("div");
            div.innerHTML = '<v:shape adj="1"/>';
            var shape = div.firstChild;
            shape.style.behavior = "url(#default#VML)";
            return shape && typeof shape.adj === "object";
          } catch (e) {
            return false;
          }
        })();
        var mac = navigator.platform.indexOf("Mac") === 0;
        var linux = navigator.platform.indexOf("Linux") === 0;
        function userAgentContains(str) {
          return navigator.userAgent.toLowerCase().indexOf(str) >= 0;
        }
        var Browser = {
          ie,
          ielt9,
          edge,
          webkit,
          android,
          android23,
          androidStock,
          opera,
          chrome,
          gecko,
          safari,
          phantom,
          opera12,
          win,
          ie3d,
          webkit3d,
          gecko3d,
          any3d,
          mobile,
          mobileWebkit,
          mobileWebkit3d,
          msPointer,
          pointer,
          touch,
          touchNative,
          mobileOpera,
          mobileGecko,
          retina,
          passiveEvents,
          canvas: canvas$1,
          svg: svg$1,
          vml,
          inlineSvg,
          mac,
          linux
        };
        var POINTER_DOWN = Browser.msPointer ? "MSPointerDown" : "pointerdown";
        var POINTER_MOVE = Browser.msPointer ? "MSPointerMove" : "pointermove";
        var POINTER_UP = Browser.msPointer ? "MSPointerUp" : "pointerup";
        var POINTER_CANCEL = Browser.msPointer ? "MSPointerCancel" : "pointercancel";
        var pEvent = {
          touchstart: POINTER_DOWN,
          touchmove: POINTER_MOVE,
          touchend: POINTER_UP,
          touchcancel: POINTER_CANCEL
        };
        var handle = {
          touchstart: _onPointerStart,
          touchmove: _handlePointer,
          touchend: _handlePointer,
          touchcancel: _handlePointer
        };
        var _pointers = {};
        var _pointerDocListener = false;
        function addPointerListener(obj, type, handler) {
          if (type === "touchstart") {
            _addPointerDocListener();
          }
          if (!handle[type]) {
            console.warn("wrong event specified:", type);
            return falseFn;
          }
          handler = handle[type].bind(this, handler);
          obj.addEventListener(pEvent[type], handler, false);
          return handler;
        }
        function removePointerListener(obj, type, handler) {
          if (!pEvent[type]) {
            console.warn("wrong event specified:", type);
            return;
          }
          obj.removeEventListener(pEvent[type], handler, false);
        }
        function _globalPointerDown(e) {
          _pointers[e.pointerId] = e;
        }
        function _globalPointerMove(e) {
          if (_pointers[e.pointerId]) {
            _pointers[e.pointerId] = e;
          }
        }
        function _globalPointerUp(e) {
          delete _pointers[e.pointerId];
        }
        function _addPointerDocListener() {
          if (!_pointerDocListener) {
            document.addEventListener(POINTER_DOWN, _globalPointerDown, true);
            document.addEventListener(POINTER_MOVE, _globalPointerMove, true);
            document.addEventListener(POINTER_UP, _globalPointerUp, true);
            document.addEventListener(POINTER_CANCEL, _globalPointerUp, true);
            _pointerDocListener = true;
          }
        }
        function _handlePointer(handler, e) {
          if (e.pointerType === (e.MSPOINTER_TYPE_MOUSE || "mouse")) {
            return;
          }
          e.touches = [];
          for (var i in _pointers) {
            e.touches.push(_pointers[i]);
          }
          e.changedTouches = [e];
          handler(e);
        }
        function _onPointerStart(handler, e) {
          if (e.MSPOINTER_TYPE_TOUCH && e.pointerType === e.MSPOINTER_TYPE_TOUCH) {
            preventDefault(e);
          }
          _handlePointer(handler, e);
        }
        function makeDblclick(event) {
          var newEvent = {}, prop, i;
          for (i in event) {
            prop = event[i];
            newEvent[i] = prop && prop.bind ? prop.bind(event) : prop;
          }
          event = newEvent;
          newEvent.type = "dblclick";
          newEvent.detail = 2;
          newEvent.isTrusted = false;
          newEvent._simulated = true;
          return newEvent;
        }
        var delay = 200;
        function addDoubleTapListener(obj, handler) {
          obj.addEventListener("dblclick", handler);
          var last = 0, detail;
          function simDblclick(e) {
            if (e.detail !== 1) {
              detail = e.detail;
              return;
            }
            if (e.pointerType === "mouse" || e.sourceCapabilities && !e.sourceCapabilities.firesTouchEvents) {
              return;
            }
            var path = getPropagationPath(e);
            if (path.some(function(el) {
              return el instanceof HTMLLabelElement && el.attributes.for;
            }) && !path.some(function(el) {
              return el instanceof HTMLInputElement || el instanceof HTMLSelectElement;
            })) {
              return;
            }
            var now = Date.now();
            if (now - last <= delay) {
              detail++;
              if (detail === 2) {
                handler(makeDblclick(e));
              }
            } else {
              detail = 1;
            }
            last = now;
          }
          obj.addEventListener("click", simDblclick);
          return {
            dblclick: handler,
            simDblclick
          };
        }
        function removeDoubleTapListener(obj, handlers) {
          obj.removeEventListener("dblclick", handlers.dblclick);
          obj.removeEventListener("click", handlers.simDblclick);
        }
        var TRANSFORM = testProp(
          ["transform", "webkitTransform", "OTransform", "MozTransform", "msTransform"]
        );
        var TRANSITION = testProp(
          ["webkitTransition", "transition", "OTransition", "MozTransition", "msTransition"]
        );
        var TRANSITION_END = TRANSITION === "webkitTransition" || TRANSITION === "OTransition" ? TRANSITION + "End" : "transitionend";
        function get(id) {
          return typeof id === "string" ? document.getElementById(id) : id;
        }
        function getStyle(el, style2) {
          var value = el.style[style2] || el.currentStyle && el.currentStyle[style2];
          if ((!value || value === "auto") && document.defaultView) {
            var css = document.defaultView.getComputedStyle(el, null);
            value = css ? css[style2] : null;
          }
          return value === "auto" ? null : value;
        }
        function create$1(tagName, className, container) {
          var el = document.createElement(tagName);
          el.className = className || "";
          if (container) {
            container.appendChild(el);
          }
          return el;
        }
        function remove(el) {
          var parent = el.parentNode;
          if (parent) {
            parent.removeChild(el);
          }
        }
        function empty(el) {
          while (el.firstChild) {
            el.removeChild(el.firstChild);
          }
        }
        function toFront(el) {
          var parent = el.parentNode;
          if (parent && parent.lastChild !== el) {
            parent.appendChild(el);
          }
        }
        function toBack(el) {
          var parent = el.parentNode;
          if (parent && parent.firstChild !== el) {
            parent.insertBefore(el, parent.firstChild);
          }
        }
        function hasClass(el, name) {
          if (el.classList !== void 0) {
            return el.classList.contains(name);
          }
          var className = getClass(el);
          return className.length > 0 && new RegExp("(^|\\s)" + name + "(\\s|$)").test(className);
        }
        function addClass(el, name) {
          if (el.classList !== void 0) {
            var classes = splitWords(name);
            for (var i = 0, len = classes.length; i < len; i++) {
              el.classList.add(classes[i]);
            }
          } else if (!hasClass(el, name)) {
            var className = getClass(el);
            setClass(el, (className ? className + " " : "") + name);
          }
        }
        function removeClass(el, name) {
          if (el.classList !== void 0) {
            el.classList.remove(name);
          } else {
            setClass(el, trim((" " + getClass(el) + " ").replace(" " + name + " ", " ")));
          }
        }
        function setClass(el, name) {
          if (el.className.baseVal === void 0) {
            el.className = name;
          } else {
            el.className.baseVal = name;
          }
        }
        function getClass(el) {
          if (el.correspondingElement) {
            el = el.correspondingElement;
          }
          return el.className.baseVal === void 0 ? el.className : el.className.baseVal;
        }
        function setOpacity(el, value) {
          if ("opacity" in el.style) {
            el.style.opacity = value;
          } else if ("filter" in el.style) {
            _setOpacityIE(el, value);
          }
        }
        function _setOpacityIE(el, value) {
          var filter = false, filterName = "DXImageTransform.Microsoft.Alpha";
          try {
            filter = el.filters.item(filterName);
          } catch (e) {
            if (value === 1) {
              return;
            }
          }
          value = Math.round(value * 100);
          if (filter) {
            filter.Enabled = value !== 100;
            filter.Opacity = value;
          } else {
            el.style.filter += " progid:" + filterName + "(opacity=" + value + ")";
          }
        }
        function testProp(props) {
          var style2 = document.documentElement.style;
          for (var i = 0; i < props.length; i++) {
            if (props[i] in style2) {
              return props[i];
            }
          }
          return false;
        }
        function setTransform(el, offset, scale2) {
          var pos = offset || new Point(0, 0);
          el.style[TRANSFORM] = (Browser.ie3d ? "translate(" + pos.x + "px," + pos.y + "px)" : "translate3d(" + pos.x + "px," + pos.y + "px,0)") + (scale2 ? " scale(" + scale2 + ")" : "");
        }
        function setPosition(el, point) {
          el._leaflet_pos = point;
          if (Browser.any3d) {
            setTransform(el, point);
          } else {
            el.style.left = point.x + "px";
            el.style.top = point.y + "px";
          }
        }
        function getPosition(el) {
          return el._leaflet_pos || new Point(0, 0);
        }
        var disableTextSelection;
        var enableTextSelection;
        var _userSelect;
        if ("onselectstart" in document) {
          disableTextSelection = function() {
            on(window, "selectstart", preventDefault);
          };
          enableTextSelection = function() {
            off(window, "selectstart", preventDefault);
          };
        } else {
          var userSelectProperty = testProp(
            ["userSelect", "WebkitUserSelect", "OUserSelect", "MozUserSelect", "msUserSelect"]
          );
          disableTextSelection = function() {
            if (userSelectProperty) {
              var style2 = document.documentElement.style;
              _userSelect = style2[userSelectProperty];
              style2[userSelectProperty] = "none";
            }
          };
          enableTextSelection = function() {
            if (userSelectProperty) {
              document.documentElement.style[userSelectProperty] = _userSelect;
              _userSelect = void 0;
            }
          };
        }
        function disableImageDrag() {
          on(window, "dragstart", preventDefault);
        }
        function enableImageDrag() {
          off(window, "dragstart", preventDefault);
        }
        var _outlineElement, _outlineStyle;
        function preventOutline(element) {
          while (element.tabIndex === -1) {
            element = element.parentNode;
          }
          if (!element.style) {
            return;
          }
          restoreOutline();
          _outlineElement = element;
          _outlineStyle = element.style.outlineStyle;
          element.style.outlineStyle = "none";
          on(window, "keydown", restoreOutline);
        }
        function restoreOutline() {
          if (!_outlineElement) {
            return;
          }
          _outlineElement.style.outlineStyle = _outlineStyle;
          _outlineElement = void 0;
          _outlineStyle = void 0;
          off(window, "keydown", restoreOutline);
        }
        function getSizedParentNode(element) {
          do {
            element = element.parentNode;
          } while ((!element.offsetWidth || !element.offsetHeight) && element !== document.body);
          return element;
        }
        function getScale(element) {
          var rect = element.getBoundingClientRect();
          return {
            x: rect.width / element.offsetWidth || 1,
            y: rect.height / element.offsetHeight || 1,
            boundingClientRect: rect
          };
        }
        var DomUtil = {
          __proto__: null,
          TRANSFORM,
          TRANSITION,
          TRANSITION_END,
          get,
          getStyle,
          create: create$1,
          remove,
          empty,
          toFront,
          toBack,
          hasClass,
          addClass,
          removeClass,
          setClass,
          getClass,
          setOpacity,
          testProp,
          setTransform,
          setPosition,
          getPosition,
          get disableTextSelection() {
            return disableTextSelection;
          },
          get enableTextSelection() {
            return enableTextSelection;
          },
          disableImageDrag,
          enableImageDrag,
          preventOutline,
          restoreOutline,
          getSizedParentNode,
          getScale
        };
        function on(obj, types, fn, context) {
          if (types && typeof types === "object") {
            for (var type in types) {
              addOne(obj, type, types[type], fn);
            }
          } else {
            types = splitWords(types);
            for (var i = 0, len = types.length; i < len; i++) {
              addOne(obj, types[i], fn, context);
            }
          }
          return this;
        }
        var eventsKey = "_leaflet_events";
        function off(obj, types, fn, context) {
          if (arguments.length === 1) {
            batchRemove(obj);
            delete obj[eventsKey];
          } else if (types && typeof types === "object") {
            for (var type in types) {
              removeOne(obj, type, types[type], fn);
            }
          } else {
            types = splitWords(types);
            if (arguments.length === 2) {
              batchRemove(obj, function(type2) {
                return indexOf(types, type2) !== -1;
              });
            } else {
              for (var i = 0, len = types.length; i < len; i++) {
                removeOne(obj, types[i], fn, context);
              }
            }
          }
          return this;
        }
        function batchRemove(obj, filterFn) {
          for (var id in obj[eventsKey]) {
            var type = id.split(/\d/)[0];
            if (!filterFn || filterFn(type)) {
              removeOne(obj, type, null, null, id);
            }
          }
        }
        var mouseSubst = {
          mouseenter: "mouseover",
          mouseleave: "mouseout",
          wheel: !("onwheel" in window) && "mousewheel"
        };
        function addOne(obj, type, fn, context) {
          var id = type + stamp(fn) + (context ? "_" + stamp(context) : "");
          if (obj[eventsKey] && obj[eventsKey][id]) {
            return this;
          }
          var handler = function(e) {
            return fn.call(context || obj, e || window.event);
          };
          var originalHandler = handler;
          if (!Browser.touchNative && Browser.pointer && type.indexOf("touch") === 0) {
            handler = addPointerListener(obj, type, handler);
          } else if (Browser.touch && type === "dblclick") {
            handler = addDoubleTapListener(obj, handler);
          } else if ("addEventListener" in obj) {
            if (type === "touchstart" || type === "touchmove" || type === "wheel" || type === "mousewheel") {
              obj.addEventListener(mouseSubst[type] || type, handler, Browser.passiveEvents ? { passive: false } : false);
            } else if (type === "mouseenter" || type === "mouseleave") {
              handler = function(e) {
                e = e || window.event;
                if (isExternalTarget(obj, e)) {
                  originalHandler(e);
                }
              };
              obj.addEventListener(mouseSubst[type], handler, false);
            } else {
              obj.addEventListener(type, originalHandler, false);
            }
          } else {
            obj.attachEvent("on" + type, handler);
          }
          obj[eventsKey] = obj[eventsKey] || {};
          obj[eventsKey][id] = handler;
        }
        function removeOne(obj, type, fn, context, id) {
          id = id || type + stamp(fn) + (context ? "_" + stamp(context) : "");
          var handler = obj[eventsKey] && obj[eventsKey][id];
          if (!handler) {
            return this;
          }
          if (!Browser.touchNative && Browser.pointer && type.indexOf("touch") === 0) {
            removePointerListener(obj, type, handler);
          } else if (Browser.touch && type === "dblclick") {
            removeDoubleTapListener(obj, handler);
          } else if ("removeEventListener" in obj) {
            obj.removeEventListener(mouseSubst[type] || type, handler, false);
          } else {
            obj.detachEvent("on" + type, handler);
          }
          obj[eventsKey][id] = null;
        }
        function stopPropagation(e) {
          if (e.stopPropagation) {
            e.stopPropagation();
          } else if (e.originalEvent) {
            e.originalEvent._stopped = true;
          } else {
            e.cancelBubble = true;
          }
          return this;
        }
        function disableScrollPropagation(el) {
          addOne(el, "wheel", stopPropagation);
          return this;
        }
        function disableClickPropagation(el) {
          on(el, "mousedown touchstart dblclick contextmenu", stopPropagation);
          el["_leaflet_disable_click"] = true;
          return this;
        }
        function preventDefault(e) {
          if (e.preventDefault) {
            e.preventDefault();
          } else {
            e.returnValue = false;
          }
          return this;
        }
        function stop(e) {
          preventDefault(e);
          stopPropagation(e);
          return this;
        }
        function getPropagationPath(ev) {
          if (ev.composedPath) {
            return ev.composedPath();
          }
          var path = [];
          var el = ev.target;
          while (el) {
            path.push(el);
            el = el.parentNode;
          }
          return path;
        }
        function getMousePosition(e, container) {
          if (!container) {
            return new Point(e.clientX, e.clientY);
          }
          var scale2 = getScale(container), offset = scale2.boundingClientRect;
          return new Point(
            // offset.left/top values are in page scale (like clientX/Y),
            // whereas clientLeft/Top (border width) values are the original values (before CSS scale applies).
            (e.clientX - offset.left) / scale2.x - container.clientLeft,
            (e.clientY - offset.top) / scale2.y - container.clientTop
          );
        }
        var wheelPxFactor = Browser.linux && Browser.chrome ? window.devicePixelRatio : Browser.mac ? window.devicePixelRatio * 3 : window.devicePixelRatio > 0 ? 2 * window.devicePixelRatio : 1;
        function getWheelDelta(e) {
          return Browser.edge ? e.wheelDeltaY / 2 : (
            // Don't trust window-geometry-based delta
            e.deltaY && e.deltaMode === 0 ? -e.deltaY / wheelPxFactor : (
              // Pixels
              e.deltaY && e.deltaMode === 1 ? -e.deltaY * 20 : (
                // Lines
                e.deltaY && e.deltaMode === 2 ? -e.deltaY * 60 : (
                  // Pages
                  e.deltaX || e.deltaZ ? 0 : (
                    // Skip horizontal/depth wheel events
                    e.wheelDelta ? (e.wheelDeltaY || e.wheelDelta) / 2 : (
                      // Legacy IE pixels
                      e.detail && Math.abs(e.detail) < 32765 ? -e.detail * 20 : (
                        // Legacy Moz lines
                        e.detail ? e.detail / -32765 * 60 : (
                          // Legacy Moz pages
                          0
                        )
                      )
                    )
                  )
                )
              )
            )
          );
        }
        function isExternalTarget(el, e) {
          var related = e.relatedTarget;
          if (!related) {
            return true;
          }
          try {
            while (related && related !== el) {
              related = related.parentNode;
            }
          } catch (err) {
            return false;
          }
          return related !== el;
        }
        var DomEvent = {
          __proto__: null,
          on,
          off,
          stopPropagation,
          disableScrollPropagation,
          disableClickPropagation,
          preventDefault,
          stop,
          getPropagationPath,
          getMousePosition,
          getWheelDelta,
          isExternalTarget,
          addListener: on,
          removeListener: off
        };
        var PosAnimation = Evented.extend({
          // @method run(el: HTMLElement, newPos: Point, duration?: Number, easeLinearity?: Number)
          // Run an animation of a given element to a new position, optionally setting
          // duration in seconds (`0.25` by default) and easing linearity factor (3rd
          // argument of the [cubic bezier curve](https://cubic-bezier.com/#0,0,.5,1),
          // `0.5` by default).
          run: function(el, newPos, duration, easeLinearity) {
            this.stop();
            this._el = el;
            this._inProgress = true;
            this._duration = duration || 0.25;
            this._easeOutPower = 1 / Math.max(easeLinearity || 0.5, 0.2);
            this._startPos = getPosition(el);
            this._offset = newPos.subtract(this._startPos);
            this._startTime = +/* @__PURE__ */ new Date();
            this.fire("start");
            this._animate();
          },
          // @method stop()
          // Stops the animation (if currently running).
          stop: function() {
            if (!this._inProgress) {
              return;
            }
            this._step(true);
            this._complete();
          },
          _animate: function() {
            this._animId = requestAnimFrame(this._animate, this);
            this._step();
          },
          _step: function(round) {
            var elapsed = +/* @__PURE__ */ new Date() - this._startTime, duration = this._duration * 1e3;
            if (elapsed < duration) {
              this._runFrame(this._easeOut(elapsed / duration), round);
            } else {
              this._runFrame(1);
              this._complete();
            }
          },
          _runFrame: function(progress, round) {
            var pos = this._startPos.add(this._offset.multiplyBy(progress));
            if (round) {
              pos._round();
            }
            setPosition(this._el, pos);
            this.fire("step");
          },
          _complete: function() {
            cancelAnimFrame(this._animId);
            this._inProgress = false;
            this.fire("end");
          },
          _easeOut: function(t) {
            return 1 - Math.pow(1 - t, this._easeOutPower);
          }
        });
        var Map2 = Evented.extend({
          options: {
            // @section Map State Options
            // @option crs: CRS = L.CRS.EPSG3857
            // The [Coordinate Reference System](#crs) to use. Don't change this if you're not
            // sure what it means.
            crs: EPSG3857,
            // @option center: LatLng = undefined
            // Initial geographic center of the map
            center: void 0,
            // @option zoom: Number = undefined
            // Initial map zoom level
            zoom: void 0,
            // @option minZoom: Number = *
            // Minimum zoom level of the map.
            // If not specified and at least one `GridLayer` or `TileLayer` is in the map,
            // the lowest of their `minZoom` options will be used instead.
            minZoom: void 0,
            // @option maxZoom: Number = *
            // Maximum zoom level of the map.
            // If not specified and at least one `GridLayer` or `TileLayer` is in the map,
            // the highest of their `maxZoom` options will be used instead.
            maxZoom: void 0,
            // @option layers: Layer[] = []
            // Array of layers that will be added to the map initially
            layers: [],
            // @option maxBounds: LatLngBounds = null
            // When this option is set, the map restricts the view to the given
            // geographical bounds, bouncing the user back if the user tries to pan
            // outside the view. To set the restriction dynamically, use
            // [`setMaxBounds`](#map-setmaxbounds) method.
            maxBounds: void 0,
            // @option renderer: Renderer = *
            // The default method for drawing vector layers on the map. `L.SVG`
            // or `L.Canvas` by default depending on browser support.
            renderer: void 0,
            // @section Animation Options
            // @option zoomAnimation: Boolean = true
            // Whether the map zoom animation is enabled. By default it's enabled
            // in all browsers that support CSS3 Transitions except Android.
            zoomAnimation: true,
            // @option zoomAnimationThreshold: Number = 4
            // Won't animate zoom if the zoom difference exceeds this value.
            zoomAnimationThreshold: 4,
            // @option fadeAnimation: Boolean = true
            // Whether the tile fade animation is enabled. By default it's enabled
            // in all browsers that support CSS3 Transitions except Android.
            fadeAnimation: true,
            // @option markerZoomAnimation: Boolean = true
            // Whether markers animate their zoom with the zoom animation, if disabled
            // they will disappear for the length of the animation. By default it's
            // enabled in all browsers that support CSS3 Transitions except Android.
            markerZoomAnimation: true,
            // @option transform3DLimit: Number = 2^23
            // Defines the maximum size of a CSS translation transform. The default
            // value should not be changed unless a web browser positions layers in
            // the wrong place after doing a large `panBy`.
            transform3DLimit: 8388608,
            // Precision limit of a 32-bit float
            // @section Interaction Options
            // @option zoomSnap: Number = 1
            // Forces the map's zoom level to always be a multiple of this, particularly
            // right after a [`fitBounds()`](#map-fitbounds) or a pinch-zoom.
            // By default, the zoom level snaps to the nearest integer; lower values
            // (e.g. `0.5` or `0.1`) allow for greater granularity. A value of `0`
            // means the zoom level will not be snapped after `fitBounds` or a pinch-zoom.
            zoomSnap: 1,
            // @option zoomDelta: Number = 1
            // Controls how much the map's zoom level will change after a
            // [`zoomIn()`](#map-zoomin), [`zoomOut()`](#map-zoomout), pressing `+`
            // or `-` on the keyboard, or using the [zoom controls](#control-zoom).
            // Values smaller than `1` (e.g. `0.5`) allow for greater granularity.
            zoomDelta: 1,
            // @option trackResize: Boolean = true
            // Whether the map automatically handles browser window resize to update itself.
            trackResize: true
          },
          initialize: function(id, options) {
            options = setOptions(this, options);
            this._handlers = [];
            this._layers = {};
            this._zoomBoundLayers = {};
            this._sizeChanged = true;
            this._initContainer(id);
            this._initLayout();
            this._onResize = bind(this._onResize, this);
            this._initEvents();
            if (options.maxBounds) {
              this.setMaxBounds(options.maxBounds);
            }
            if (options.zoom !== void 0) {
              this._zoom = this._limitZoom(options.zoom);
            }
            if (options.center && options.zoom !== void 0) {
              this.setView(toLatLng(options.center), options.zoom, { reset: true });
            }
            this.callInitHooks();
            this._zoomAnimated = TRANSITION && Browser.any3d && !Browser.mobileOpera && this.options.zoomAnimation;
            if (this._zoomAnimated) {
              this._createAnimProxy();
              on(this._proxy, TRANSITION_END, this._catchTransitionEnd, this);
            }
            this._addLayers(this.options.layers);
          },
          // @section Methods for modifying map state
          // @method setView(center: LatLng, zoom: Number, options?: Zoom/pan options): this
          // Sets the view of the map (geographical center and zoom) with the given
          // animation options.
          setView: function(center, zoom2, options) {
            zoom2 = zoom2 === void 0 ? this._zoom : this._limitZoom(zoom2);
            center = this._limitCenter(toLatLng(center), zoom2, this.options.maxBounds);
            options = options || {};
            this._stop();
            if (this._loaded && !options.reset && options !== true) {
              if (options.animate !== void 0) {
                options.zoom = extend({ animate: options.animate }, options.zoom);
                options.pan = extend({ animate: options.animate, duration: options.duration }, options.pan);
              }
              var moved = this._zoom !== zoom2 ? this._tryAnimatedZoom && this._tryAnimatedZoom(center, zoom2, options.zoom) : this._tryAnimatedPan(center, options.pan);
              if (moved) {
                clearTimeout(this._sizeTimer);
                return this;
              }
            }
            this._resetView(center, zoom2, options.pan && options.pan.noMoveStart);
            return this;
          },
          // @method setZoom(zoom: Number, options?: Zoom/pan options): this
          // Sets the zoom of the map.
          setZoom: function(zoom2, options) {
            if (!this._loaded) {
              this._zoom = zoom2;
              return this;
            }
            return this.setView(this.getCenter(), zoom2, { zoom: options });
          },
          // @method zoomIn(delta?: Number, options?: Zoom options): this
          // Increases the zoom of the map by `delta` ([`zoomDelta`](#map-zoomdelta) by default).
          zoomIn: function(delta, options) {
            delta = delta || (Browser.any3d ? this.options.zoomDelta : 1);
            return this.setZoom(this._zoom + delta, options);
          },
          // @method zoomOut(delta?: Number, options?: Zoom options): this
          // Decreases the zoom of the map by `delta` ([`zoomDelta`](#map-zoomdelta) by default).
          zoomOut: function(delta, options) {
            delta = delta || (Browser.any3d ? this.options.zoomDelta : 1);
            return this.setZoom(this._zoom - delta, options);
          },
          // @method setZoomAround(latlng: LatLng, zoom: Number, options: Zoom options): this
          // Zooms the map while keeping a specified geographical point on the map
          // stationary (e.g. used internally for scroll zoom and double-click zoom).
          // @alternative
          // @method setZoomAround(offset: Point, zoom: Number, options: Zoom options): this
          // Zooms the map while keeping a specified pixel on the map (relative to the top-left corner) stationary.
          setZoomAround: function(latlng, zoom2, options) {
            var scale2 = this.getZoomScale(zoom2), viewHalf = this.getSize().divideBy(2), containerPoint = latlng instanceof Point ? latlng : this.latLngToContainerPoint(latlng), centerOffset = containerPoint.subtract(viewHalf).multiplyBy(1 - 1 / scale2), newCenter = this.containerPointToLatLng(viewHalf.add(centerOffset));
            return this.setView(newCenter, zoom2, { zoom: options });
          },
          _getBoundsCenterZoom: function(bounds, options) {
            options = options || {};
            bounds = bounds.getBounds ? bounds.getBounds() : toLatLngBounds(bounds);
            var paddingTL = toPoint(options.paddingTopLeft || options.padding || [0, 0]), paddingBR = toPoint(options.paddingBottomRight || options.padding || [0, 0]), zoom2 = this.getBoundsZoom(bounds, false, paddingTL.add(paddingBR));
            zoom2 = typeof options.maxZoom === "number" ? Math.min(options.maxZoom, zoom2) : zoom2;
            if (zoom2 === Infinity) {
              return {
                center: bounds.getCenter(),
                zoom: zoom2
              };
            }
            var paddingOffset = paddingBR.subtract(paddingTL).divideBy(2), swPoint = this.project(bounds.getSouthWest(), zoom2), nePoint = this.project(bounds.getNorthEast(), zoom2), center = this.unproject(swPoint.add(nePoint).divideBy(2).add(paddingOffset), zoom2);
            return {
              center,
              zoom: zoom2
            };
          },
          // @method fitBounds(bounds: LatLngBounds, options?: fitBounds options): this
          // Sets a map view that contains the given geographical bounds with the
          // maximum zoom level possible.
          fitBounds: function(bounds, options) {
            bounds = toLatLngBounds(bounds);
            if (!bounds.isValid()) {
              throw new Error("Bounds are not valid.");
            }
            var target = this._getBoundsCenterZoom(bounds, options);
            return this.setView(target.center, target.zoom, options);
          },
          // @method fitWorld(options?: fitBounds options): this
          // Sets a map view that mostly contains the whole world with the maximum
          // zoom level possible.
          fitWorld: function(options) {
            return this.fitBounds([[-90, -180], [90, 180]], options);
          },
          // @method panTo(latlng: LatLng, options?: Pan options): this
          // Pans the map to a given center.
          panTo: function(center, options) {
            return this.setView(center, this._zoom, { pan: options });
          },
          // @method panBy(offset: Point, options?: Pan options): this
          // Pans the map by a given number of pixels (animated).
          panBy: function(offset, options) {
            offset = toPoint(offset).round();
            options = options || {};
            if (!offset.x && !offset.y) {
              return this.fire("moveend");
            }
            if (options.animate !== true && !this.getSize().contains(offset)) {
              this._resetView(this.unproject(this.project(this.getCenter()).add(offset)), this.getZoom());
              return this;
            }
            if (!this._panAnim) {
              this._panAnim = new PosAnimation();
              this._panAnim.on({
                "step": this._onPanTransitionStep,
                "end": this._onPanTransitionEnd
              }, this);
            }
            if (!options.noMoveStart) {
              this.fire("movestart");
            }
            if (options.animate !== false) {
              addClass(this._mapPane, "leaflet-pan-anim");
              var newPos = this._getMapPanePos().subtract(offset).round();
              this._panAnim.run(this._mapPane, newPos, options.duration || 0.25, options.easeLinearity);
            } else {
              this._rawPanBy(offset);
              this.fire("move").fire("moveend");
            }
            return this;
          },
          // @method flyTo(latlng: LatLng, zoom?: Number, options?: Zoom/pan options): this
          // Sets the view of the map (geographical center and zoom) performing a smooth
          // pan-zoom animation.
          flyTo: function(targetCenter, targetZoom, options) {
            options = options || {};
            if (options.animate === false || !Browser.any3d) {
              return this.setView(targetCenter, targetZoom, options);
            }
            this._stop();
            var from = this.project(this.getCenter()), to = this.project(targetCenter), size = this.getSize(), startZoom = this._zoom;
            targetCenter = toLatLng(targetCenter);
            targetZoom = targetZoom === void 0 ? startZoom : targetZoom;
            var w0 = Math.max(size.x, size.y), w1 = w0 * this.getZoomScale(startZoom, targetZoom), u1 = to.distanceTo(from) || 1, rho = 1.42, rho2 = rho * rho;
            function r(i) {
              var s1 = i ? -1 : 1, s2 = i ? w1 : w0, t1 = w1 * w1 - w0 * w0 + s1 * rho2 * rho2 * u1 * u1, b1 = 2 * s2 * rho2 * u1, b = t1 / b1, sq = Math.sqrt(b * b + 1) - b;
              var log = sq < 1e-9 ? -18 : Math.log(sq);
              return log;
            }
            function sinh(n) {
              return (Math.exp(n) - Math.exp(-n)) / 2;
            }
            function cosh(n) {
              return (Math.exp(n) + Math.exp(-n)) / 2;
            }
            function tanh(n) {
              return sinh(n) / cosh(n);
            }
            var r0 = r(0);
            function w(s) {
              return w0 * (cosh(r0) / cosh(r0 + rho * s));
            }
            function u(s) {
              return w0 * (cosh(r0) * tanh(r0 + rho * s) - sinh(r0)) / rho2;
            }
            function easeOut(t) {
              return 1 - Math.pow(1 - t, 1.5);
            }
            var start = Date.now(), S = (r(1) - r0) / rho, duration = options.duration ? 1e3 * options.duration : 1e3 * S * 0.8;
            function frame() {
              var t = (Date.now() - start) / duration, s = easeOut(t) * S;
              if (t <= 1) {
                this._flyToFrame = requestAnimFrame(frame, this);
                this._move(
                  this.unproject(from.add(to.subtract(from).multiplyBy(u(s) / u1)), startZoom),
                  this.getScaleZoom(w0 / w(s), startZoom),
                  { flyTo: true }
                );
              } else {
                this._move(targetCenter, targetZoom)._moveEnd(true);
              }
            }
            this._moveStart(true, options.noMoveStart);
            frame.call(this);
            return this;
          },
          // @method flyToBounds(bounds: LatLngBounds, options?: fitBounds options): this
          // Sets the view of the map with a smooth animation like [`flyTo`](#map-flyto),
          // but takes a bounds parameter like [`fitBounds`](#map-fitbounds).
          flyToBounds: function(bounds, options) {
            var target = this._getBoundsCenterZoom(bounds, options);
            return this.flyTo(target.center, target.zoom, options);
          },
          // @method setMaxBounds(bounds: LatLngBounds): this
          // Restricts the map view to the given bounds (see the [maxBounds](#map-maxbounds) option).
          setMaxBounds: function(bounds) {
            bounds = toLatLngBounds(bounds);
            if (this.listens("moveend", this._panInsideMaxBounds)) {
              this.off("moveend", this._panInsideMaxBounds);
            }
            if (!bounds.isValid()) {
              this.options.maxBounds = null;
              return this;
            }
            this.options.maxBounds = bounds;
            if (this._loaded) {
              this._panInsideMaxBounds();
            }
            return this.on("moveend", this._panInsideMaxBounds);
          },
          // @method setMinZoom(zoom: Number): this
          // Sets the lower limit for the available zoom levels (see the [minZoom](#map-minzoom) option).
          setMinZoom: function(zoom2) {
            var oldZoom = this.options.minZoom;
            this.options.minZoom = zoom2;
            if (this._loaded && oldZoom !== zoom2) {
              this.fire("zoomlevelschange");
              if (this.getZoom() < this.options.minZoom) {
                return this.setZoom(zoom2);
              }
            }
            return this;
          },
          // @method setMaxZoom(zoom: Number): this
          // Sets the upper limit for the available zoom levels (see the [maxZoom](#map-maxzoom) option).
          setMaxZoom: function(zoom2) {
            var oldZoom = this.options.maxZoom;
            this.options.maxZoom = zoom2;
            if (this._loaded && oldZoom !== zoom2) {
              this.fire("zoomlevelschange");
              if (this.getZoom() > this.options.maxZoom) {
                return this.setZoom(zoom2);
              }
            }
            return this;
          },
          // @method panInsideBounds(bounds: LatLngBounds, options?: Pan options): this
          // Pans the map to the closest view that would lie inside the given bounds (if it's not already), controlling the animation using the options specific, if any.
          panInsideBounds: function(bounds, options) {
            this._enforcingBounds = true;
            var center = this.getCenter(), newCenter = this._limitCenter(center, this._zoom, toLatLngBounds(bounds));
            if (!center.equals(newCenter)) {
              this.panTo(newCenter, options);
            }
            this._enforcingBounds = false;
            return this;
          },
          // @method panInside(latlng: LatLng, options?: padding options): this
          // Pans the map the minimum amount to make the `latlng` visible. Use
          // padding options to fit the display to more restricted bounds.
          // If `latlng` is already within the (optionally padded) display bounds,
          // the map will not be panned.
          panInside: function(latlng, options) {
            options = options || {};
            var paddingTL = toPoint(options.paddingTopLeft || options.padding || [0, 0]), paddingBR = toPoint(options.paddingBottomRight || options.padding || [0, 0]), pixelCenter = this.project(this.getCenter()), pixelPoint = this.project(latlng), pixelBounds = this.getPixelBounds(), paddedBounds = toBounds([pixelBounds.min.add(paddingTL), pixelBounds.max.subtract(paddingBR)]), paddedSize = paddedBounds.getSize();
            if (!paddedBounds.contains(pixelPoint)) {
              this._enforcingBounds = true;
              var centerOffset = pixelPoint.subtract(paddedBounds.getCenter());
              var offset = paddedBounds.extend(pixelPoint).getSize().subtract(paddedSize);
              pixelCenter.x += centerOffset.x < 0 ? -offset.x : offset.x;
              pixelCenter.y += centerOffset.y < 0 ? -offset.y : offset.y;
              this.panTo(this.unproject(pixelCenter), options);
              this._enforcingBounds = false;
            }
            return this;
          },
          // @method invalidateSize(options: Zoom/pan options): this
          // Checks if the map container size changed and updates the map if so —
          // call it after you've changed the map size dynamically, also animating
          // pan by default. If `options.pan` is `false`, panning will not occur.
          // If `options.debounceMoveend` is `true`, it will delay `moveend` event so
          // that it doesn't happen often even if the method is called many
          // times in a row.
          // @alternative
          // @method invalidateSize(animate: Boolean): this
          // Checks if the map container size changed and updates the map if so —
          // call it after you've changed the map size dynamically, also animating
          // pan by default.
          invalidateSize: function(options) {
            if (!this._loaded) {
              return this;
            }
            options = extend({
              animate: false,
              pan: true
            }, options === true ? { animate: true } : options);
            var oldSize = this.getSize();
            this._sizeChanged = true;
            this._lastCenter = null;
            var newSize = this.getSize(), oldCenter = oldSize.divideBy(2).round(), newCenter = newSize.divideBy(2).round(), offset = oldCenter.subtract(newCenter);
            if (!offset.x && !offset.y) {
              return this;
            }
            if (options.animate && options.pan) {
              this.panBy(offset);
            } else {
              if (options.pan) {
                this._rawPanBy(offset);
              }
              this.fire("move");
              if (options.debounceMoveend) {
                clearTimeout(this._sizeTimer);
                this._sizeTimer = setTimeout(bind(this.fire, this, "moveend"), 200);
              } else {
                this.fire("moveend");
              }
            }
            return this.fire("resize", {
              oldSize,
              newSize
            });
          },
          // @section Methods for modifying map state
          // @method stop(): this
          // Stops the currently running `panTo` or `flyTo` animation, if any.
          stop: function() {
            this.setZoom(this._limitZoom(this._zoom));
            if (!this.options.zoomSnap) {
              this.fire("viewreset");
            }
            return this._stop();
          },
          // @section Geolocation methods
          // @method locate(options?: Locate options): this
          // Tries to locate the user using the Geolocation API, firing a [`locationfound`](#map-locationfound)
          // event with location data on success or a [`locationerror`](#map-locationerror) event on failure,
          // and optionally sets the map view to the user's location with respect to
          // detection accuracy (or to the world view if geolocation failed).
          // Note that, if your page doesn't use HTTPS, this method will fail in
          // modern browsers ([Chrome 50 and newer](https://sites.google.com/a/chromium.org/dev/Home/chromium-security/deprecating-powerful-features-on-insecure-origins))
          // See `Locate options` for more details.
          locate: function(options) {
            options = this._locateOptions = extend({
              timeout: 1e4,
              watch: false
              // setView: false
              // maxZoom: <Number>
              // maximumAge: 0
              // enableHighAccuracy: false
            }, options);
            if (!("geolocation" in navigator)) {
              this._handleGeolocationError({
                code: 0,
                message: "Geolocation not supported."
              });
              return this;
            }
            var onResponse = bind(this._handleGeolocationResponse, this), onError = bind(this._handleGeolocationError, this);
            if (options.watch) {
              this._locationWatchId = navigator.geolocation.watchPosition(onResponse, onError, options);
            } else {
              navigator.geolocation.getCurrentPosition(onResponse, onError, options);
            }
            return this;
          },
          // @method stopLocate(): this
          // Stops watching location previously initiated by `map.locate({watch: true})`
          // and aborts resetting the map view if map.locate was called with
          // `{setView: true}`.
          stopLocate: function() {
            if (navigator.geolocation && navigator.geolocation.clearWatch) {
              navigator.geolocation.clearWatch(this._locationWatchId);
            }
            if (this._locateOptions) {
              this._locateOptions.setView = false;
            }
            return this;
          },
          _handleGeolocationError: function(error) {
            if (!this._container._leaflet_id) {
              return;
            }
            var c = error.code, message = error.message || (c === 1 ? "permission denied" : c === 2 ? "position unavailable" : "timeout");
            if (this._locateOptions.setView && !this._loaded) {
              this.fitWorld();
            }
            this.fire("locationerror", {
              code: c,
              message: "Geolocation error: " + message + "."
            });
          },
          _handleGeolocationResponse: function(pos) {
            if (!this._container._leaflet_id) {
              return;
            }
            var lat = pos.coords.latitude, lng = pos.coords.longitude, latlng = new LatLng(lat, lng), bounds = latlng.toBounds(pos.coords.accuracy * 2), options = this._locateOptions;
            if (options.setView) {
              var zoom2 = this.getBoundsZoom(bounds);
              this.setView(latlng, options.maxZoom ? Math.min(zoom2, options.maxZoom) : zoom2);
            }
            var data = {
              latlng,
              bounds,
              timestamp: pos.timestamp
            };
            for (var i in pos.coords) {
              if (typeof pos.coords[i] === "number") {
                data[i] = pos.coords[i];
              }
            }
            this.fire("locationfound", data);
          },
          // TODO Appropriate docs section?
          // @section Other Methods
          // @method addHandler(name: String, HandlerClass: Function): this
          // Adds a new `Handler` to the map, given its name and constructor function.
          addHandler: function(name, HandlerClass) {
            if (!HandlerClass) {
              return this;
            }
            var handler = this[name] = new HandlerClass(this);
            this._handlers.push(handler);
            if (this.options[name]) {
              handler.enable();
            }
            return this;
          },
          // @method remove(): this
          // Destroys the map and clears all related event listeners.
          remove: function() {
            this._initEvents(true);
            if (this.options.maxBounds) {
              this.off("moveend", this._panInsideMaxBounds);
            }
            if (this._containerId !== this._container._leaflet_id) {
              throw new Error("Map container is being reused by another instance");
            }
            try {
              delete this._container._leaflet_id;
              delete this._containerId;
            } catch (e) {
              this._container._leaflet_id = void 0;
              this._containerId = void 0;
            }
            if (this._locationWatchId !== void 0) {
              this.stopLocate();
            }
            this._stop();
            remove(this._mapPane);
            if (this._clearControlPos) {
              this._clearControlPos();
            }
            if (this._resizeRequest) {
              cancelAnimFrame(this._resizeRequest);
              this._resizeRequest = null;
            }
            this._clearHandlers();
            if (this._loaded) {
              this.fire("unload");
            }
            var i;
            for (i in this._layers) {
              this._layers[i].remove();
            }
            for (i in this._panes) {
              remove(this._panes[i]);
            }
            this._layers = [];
            this._panes = [];
            delete this._mapPane;
            delete this._renderer;
            return this;
          },
          // @section Other Methods
          // @method createPane(name: String, container?: HTMLElement): HTMLElement
          // Creates a new [map pane](#map-pane) with the given name if it doesn't exist already,
          // then returns it. The pane is created as a child of `container`, or
          // as a child of the main map pane if not set.
          createPane: function(name, container) {
            var className = "leaflet-pane" + (name ? " leaflet-" + name.replace("Pane", "") + "-pane" : ""), pane = create$1("div", className, container || this._mapPane);
            if (name) {
              this._panes[name] = pane;
            }
            return pane;
          },
          // @section Methods for Getting Map State
          // @method getCenter(): LatLng
          // Returns the geographical center of the map view
          getCenter: function() {
            this._checkIfLoaded();
            if (this._lastCenter && !this._moved()) {
              return this._lastCenter.clone();
            }
            return this.layerPointToLatLng(this._getCenterLayerPoint());
          },
          // @method getZoom(): Number
          // Returns the current zoom level of the map view
          getZoom: function() {
            return this._zoom;
          },
          // @method getBounds(): LatLngBounds
          // Returns the geographical bounds visible in the current map view
          getBounds: function() {
            var bounds = this.getPixelBounds(), sw = this.unproject(bounds.getBottomLeft()), ne = this.unproject(bounds.getTopRight());
            return new LatLngBounds(sw, ne);
          },
          // @method getMinZoom(): Number
          // Returns the minimum zoom level of the map (if set in the `minZoom` option of the map or of any layers), or `0` by default.
          getMinZoom: function() {
            return this.options.minZoom === void 0 ? this._layersMinZoom || 0 : this.options.minZoom;
          },
          // @method getMaxZoom(): Number
          // Returns the maximum zoom level of the map (if set in the `maxZoom` option of the map or of any layers).
          getMaxZoom: function() {
            return this.options.maxZoom === void 0 ? this._layersMaxZoom === void 0 ? Infinity : this._layersMaxZoom : this.options.maxZoom;
          },
          // @method getBoundsZoom(bounds: LatLngBounds, inside?: Boolean, padding?: Point): Number
          // Returns the maximum zoom level on which the given bounds fit to the map
          // view in its entirety. If `inside` (optional) is set to `true`, the method
          // instead returns the minimum zoom level on which the map view fits into
          // the given bounds in its entirety.
          getBoundsZoom: function(bounds, inside, padding) {
            bounds = toLatLngBounds(bounds);
            padding = toPoint(padding || [0, 0]);
            var zoom2 = this.getZoom() || 0, min = this.getMinZoom(), max = this.getMaxZoom(), nw = bounds.getNorthWest(), se = bounds.getSouthEast(), size = this.getSize().subtract(padding), boundsSize = toBounds(this.project(se, zoom2), this.project(nw, zoom2)).getSize(), snap = Browser.any3d ? this.options.zoomSnap : 1, scalex = size.x / boundsSize.x, scaley = size.y / boundsSize.y, scale2 = inside ? Math.max(scalex, scaley) : Math.min(scalex, scaley);
            zoom2 = this.getScaleZoom(scale2, zoom2);
            if (snap) {
              zoom2 = Math.round(zoom2 / (snap / 100)) * (snap / 100);
              zoom2 = inside ? Math.ceil(zoom2 / snap) * snap : Math.floor(zoom2 / snap) * snap;
            }
            return Math.max(min, Math.min(max, zoom2));
          },
          // @method getSize(): Point
          // Returns the current size of the map container (in pixels).
          getSize: function() {
            if (!this._size || this._sizeChanged) {
              this._size = new Point(
                this._container.clientWidth || 0,
                this._container.clientHeight || 0
              );
              this._sizeChanged = false;
            }
            return this._size.clone();
          },
          // @method getPixelBounds(): Bounds
          // Returns the bounds of the current map view in projected pixel
          // coordinates (sometimes useful in layer and overlay implementations).
          getPixelBounds: function(center, zoom2) {
            var topLeftPoint = this._getTopLeftPoint(center, zoom2);
            return new Bounds(topLeftPoint, topLeftPoint.add(this.getSize()));
          },
          // TODO: Check semantics - isn't the pixel origin the 0,0 coord relative to
          // the map pane? "left point of the map layer" can be confusing, specially
          // since there can be negative offsets.
          // @method getPixelOrigin(): Point
          // Returns the projected pixel coordinates of the top left point of
          // the map layer (useful in custom layer and overlay implementations).
          getPixelOrigin: function() {
            this._checkIfLoaded();
            return this._pixelOrigin;
          },
          // @method getPixelWorldBounds(zoom?: Number): Bounds
          // Returns the world's bounds in pixel coordinates for zoom level `zoom`.
          // If `zoom` is omitted, the map's current zoom level is used.
          getPixelWorldBounds: function(zoom2) {
            return this.options.crs.getProjectedBounds(zoom2 === void 0 ? this.getZoom() : zoom2);
          },
          // @section Other Methods
          // @method getPane(pane: String|HTMLElement): HTMLElement
          // Returns a [map pane](#map-pane), given its name or its HTML element (its identity).
          getPane: function(pane) {
            return typeof pane === "string" ? this._panes[pane] : pane;
          },
          // @method getPanes(): Object
          // Returns a plain object containing the names of all [panes](#map-pane) as keys and
          // the panes as values.
          getPanes: function() {
            return this._panes;
          },
          // @method getContainer: HTMLElement
          // Returns the HTML element that contains the map.
          getContainer: function() {
            return this._container;
          },
          // @section Conversion Methods
          // @method getZoomScale(toZoom: Number, fromZoom: Number): Number
          // Returns the scale factor to be applied to a map transition from zoom level
          // `fromZoom` to `toZoom`. Used internally to help with zoom animations.
          getZoomScale: function(toZoom, fromZoom) {
            var crs = this.options.crs;
            fromZoom = fromZoom === void 0 ? this._zoom : fromZoom;
            return crs.scale(toZoom) / crs.scale(fromZoom);
          },
          // @method getScaleZoom(scale: Number, fromZoom: Number): Number
          // Returns the zoom level that the map would end up at, if it is at `fromZoom`
          // level and everything is scaled by a factor of `scale`. Inverse of
          // [`getZoomScale`](#map-getZoomScale).
          getScaleZoom: function(scale2, fromZoom) {
            var crs = this.options.crs;
            fromZoom = fromZoom === void 0 ? this._zoom : fromZoom;
            var zoom2 = crs.zoom(scale2 * crs.scale(fromZoom));
            return isNaN(zoom2) ? Infinity : zoom2;
          },
          // @method project(latlng: LatLng, zoom: Number): Point
          // Projects a geographical coordinate `LatLng` according to the projection
          // of the map's CRS, then scales it according to `zoom` and the CRS's
          // `Transformation`. The result is pixel coordinate relative to
          // the CRS origin.
          project: function(latlng, zoom2) {
            zoom2 = zoom2 === void 0 ? this._zoom : zoom2;
            return this.options.crs.latLngToPoint(toLatLng(latlng), zoom2);
          },
          // @method unproject(point: Point, zoom: Number): LatLng
          // Inverse of [`project`](#map-project).
          unproject: function(point, zoom2) {
            zoom2 = zoom2 === void 0 ? this._zoom : zoom2;
            return this.options.crs.pointToLatLng(toPoint(point), zoom2);
          },
          // @method layerPointToLatLng(point: Point): LatLng
          // Given a pixel coordinate relative to the [origin pixel](#map-getpixelorigin),
          // returns the corresponding geographical coordinate (for the current zoom level).
          layerPointToLatLng: function(point) {
            var projectedPoint = toPoint(point).add(this.getPixelOrigin());
            return this.unproject(projectedPoint);
          },
          // @method latLngToLayerPoint(latlng: LatLng): Point
          // Given a geographical coordinate, returns the corresponding pixel coordinate
          // relative to the [origin pixel](#map-getpixelorigin).
          latLngToLayerPoint: function(latlng) {
            var projectedPoint = this.project(toLatLng(latlng))._round();
            return projectedPoint._subtract(this.getPixelOrigin());
          },
          // @method wrapLatLng(latlng: LatLng): LatLng
          // Returns a `LatLng` where `lat` and `lng` has been wrapped according to the
          // map's CRS's `wrapLat` and `wrapLng` properties, if they are outside the
          // CRS's bounds.
          // By default this means longitude is wrapped around the dateline so its
          // value is between -180 and +180 degrees.
          wrapLatLng: function(latlng) {
            return this.options.crs.wrapLatLng(toLatLng(latlng));
          },
          // @method wrapLatLngBounds(bounds: LatLngBounds): LatLngBounds
          // Returns a `LatLngBounds` with the same size as the given one, ensuring that
          // its center is within the CRS's bounds.
          // By default this means the center longitude is wrapped around the dateline so its
          // value is between -180 and +180 degrees, and the majority of the bounds
          // overlaps the CRS's bounds.
          wrapLatLngBounds: function(latlng) {
            return this.options.crs.wrapLatLngBounds(toLatLngBounds(latlng));
          },
          // @method distance(latlng1: LatLng, latlng2: LatLng): Number
          // Returns the distance between two geographical coordinates according to
          // the map's CRS. By default this measures distance in meters.
          distance: function(latlng1, latlng2) {
            return this.options.crs.distance(toLatLng(latlng1), toLatLng(latlng2));
          },
          // @method containerPointToLayerPoint(point: Point): Point
          // Given a pixel coordinate relative to the map container, returns the corresponding
          // pixel coordinate relative to the [origin pixel](#map-getpixelorigin).
          containerPointToLayerPoint: function(point) {
            return toPoint(point).subtract(this._getMapPanePos());
          },
          // @method layerPointToContainerPoint(point: Point): Point
          // Given a pixel coordinate relative to the [origin pixel](#map-getpixelorigin),
          // returns the corresponding pixel coordinate relative to the map container.
          layerPointToContainerPoint: function(point) {
            return toPoint(point).add(this._getMapPanePos());
          },
          // @method containerPointToLatLng(point: Point): LatLng
          // Given a pixel coordinate relative to the map container, returns
          // the corresponding geographical coordinate (for the current zoom level).
          containerPointToLatLng: function(point) {
            var layerPoint = this.containerPointToLayerPoint(toPoint(point));
            return this.layerPointToLatLng(layerPoint);
          },
          // @method latLngToContainerPoint(latlng: LatLng): Point
          // Given a geographical coordinate, returns the corresponding pixel coordinate
          // relative to the map container.
          latLngToContainerPoint: function(latlng) {
            return this.layerPointToContainerPoint(this.latLngToLayerPoint(toLatLng(latlng)));
          },
          // @method mouseEventToContainerPoint(ev: MouseEvent): Point
          // Given a MouseEvent object, returns the pixel coordinate relative to the
          // map container where the event took place.
          mouseEventToContainerPoint: function(e) {
            return getMousePosition(e, this._container);
          },
          // @method mouseEventToLayerPoint(ev: MouseEvent): Point
          // Given a MouseEvent object, returns the pixel coordinate relative to
          // the [origin pixel](#map-getpixelorigin) where the event took place.
          mouseEventToLayerPoint: function(e) {
            return this.containerPointToLayerPoint(this.mouseEventToContainerPoint(e));
          },
          // @method mouseEventToLatLng(ev: MouseEvent): LatLng
          // Given a MouseEvent object, returns geographical coordinate where the
          // event took place.
          mouseEventToLatLng: function(e) {
            return this.layerPointToLatLng(this.mouseEventToLayerPoint(e));
          },
          // map initialization methods
          _initContainer: function(id) {
            var container = this._container = get(id);
            if (!container) {
              throw new Error("Map container not found.");
            } else if (container._leaflet_id) {
              throw new Error("Map container is already initialized.");
            }
            on(container, "scroll", this._onScroll, this);
            this._containerId = stamp(container);
          },
          _initLayout: function() {
            var container = this._container;
            this._fadeAnimated = this.options.fadeAnimation && Browser.any3d;
            addClass(container, "leaflet-container" + (Browser.touch ? " leaflet-touch" : "") + (Browser.retina ? " leaflet-retina" : "") + (Browser.ielt9 ? " leaflet-oldie" : "") + (Browser.safari ? " leaflet-safari" : "") + (this._fadeAnimated ? " leaflet-fade-anim" : ""));
            var position = getStyle(container, "position");
            if (position !== "absolute" && position !== "relative" && position !== "fixed" && position !== "sticky") {
              container.style.position = "relative";
            }
            this._initPanes();
            if (this._initControlPos) {
              this._initControlPos();
            }
          },
          _initPanes: function() {
            var panes = this._panes = {};
            this._paneRenderers = {};
            this._mapPane = this.createPane("mapPane", this._container);
            setPosition(this._mapPane, new Point(0, 0));
            this.createPane("tilePane");
            this.createPane("overlayPane");
            this.createPane("shadowPane");
            this.createPane("markerPane");
            this.createPane("tooltipPane");
            this.createPane("popupPane");
            if (!this.options.markerZoomAnimation) {
              addClass(panes.markerPane, "leaflet-zoom-hide");
              addClass(panes.shadowPane, "leaflet-zoom-hide");
            }
          },
          // private methods that modify map state
          // @section Map state change events
          _resetView: function(center, zoom2, noMoveStart) {
            setPosition(this._mapPane, new Point(0, 0));
            var loading = !this._loaded;
            this._loaded = true;
            zoom2 = this._limitZoom(zoom2);
            this.fire("viewprereset");
            var zoomChanged = this._zoom !== zoom2;
            this._moveStart(zoomChanged, noMoveStart)._move(center, zoom2)._moveEnd(zoomChanged);
            this.fire("viewreset");
            if (loading) {
              this.fire("load");
            }
          },
          _moveStart: function(zoomChanged, noMoveStart) {
            if (zoomChanged) {
              this.fire("zoomstart");
            }
            if (!noMoveStart) {
              this.fire("movestart");
            }
            return this;
          },
          _move: function(center, zoom2, data, supressEvent) {
            if (zoom2 === void 0) {
              zoom2 = this._zoom;
            }
            var zoomChanged = this._zoom !== zoom2;
            this._zoom = zoom2;
            this._lastCenter = center;
            this._pixelOrigin = this._getNewPixelOrigin(center);
            if (!supressEvent) {
              if (zoomChanged || data && data.pinch) {
                this.fire("zoom", data);
              }
              this.fire("move", data);
            } else if (data && data.pinch) {
              this.fire("zoom", data);
            }
            return this;
          },
          _moveEnd: function(zoomChanged) {
            if (zoomChanged) {
              this.fire("zoomend");
            }
            return this.fire("moveend");
          },
          _stop: function() {
            cancelAnimFrame(this._flyToFrame);
            if (this._panAnim) {
              this._panAnim.stop();
            }
            return this;
          },
          _rawPanBy: function(offset) {
            setPosition(this._mapPane, this._getMapPanePos().subtract(offset));
          },
          _getZoomSpan: function() {
            return this.getMaxZoom() - this.getMinZoom();
          },
          _panInsideMaxBounds: function() {
            if (!this._enforcingBounds) {
              this.panInsideBounds(this.options.maxBounds);
            }
          },
          _checkIfLoaded: function() {
            if (!this._loaded) {
              throw new Error("Set map center and zoom first.");
            }
          },
          // DOM event handling
          // @section Interaction events
          _initEvents: function(remove2) {
            this._targets = {};
            this._targets[stamp(this._container)] = this;
            var onOff = remove2 ? off : on;
            onOff(this._container, "click dblclick mousedown mouseup mouseover mouseout mousemove contextmenu keypress keydown keyup", this._handleDOMEvent, this);
            if (this.options.trackResize) {
              onOff(window, "resize", this._onResize, this);
            }
            if (Browser.any3d && this.options.transform3DLimit) {
              (remove2 ? this.off : this.on).call(this, "moveend", this._onMoveEnd);
            }
          },
          _onResize: function() {
            cancelAnimFrame(this._resizeRequest);
            this._resizeRequest = requestAnimFrame(
              function() {
                this.invalidateSize({ debounceMoveend: true });
              },
              this
            );
          },
          _onScroll: function() {
            this._container.scrollTop = 0;
            this._container.scrollLeft = 0;
          },
          _onMoveEnd: function() {
            var pos = this._getMapPanePos();
            if (Math.max(Math.abs(pos.x), Math.abs(pos.y)) >= this.options.transform3DLimit) {
              this._resetView(this.getCenter(), this.getZoom());
            }
          },
          _findEventTargets: function(e, type) {
            var targets = [], target, isHover = type === "mouseout" || type === "mouseover", src = e.target || e.srcElement, dragging = false;
            while (src) {
              target = this._targets[stamp(src)];
              if (target && (type === "click" || type === "preclick") && this._draggableMoved(target)) {
                dragging = true;
                break;
              }
              if (target && target.listens(type, true)) {
                if (isHover && !isExternalTarget(src, e)) {
                  break;
                }
                targets.push(target);
                if (isHover) {
                  break;
                }
              }
              if (src === this._container) {
                break;
              }
              src = src.parentNode;
            }
            if (!targets.length && !dragging && !isHover && this.listens(type, true)) {
              targets = [this];
            }
            return targets;
          },
          _isClickDisabled: function(el) {
            while (el && el !== this._container) {
              if (el["_leaflet_disable_click"]) {
                return true;
              }
              el = el.parentNode;
            }
          },
          _handleDOMEvent: function(e) {
            var el = e.target || e.srcElement;
            if (!this._loaded || el["_leaflet_disable_events"] || e.type === "click" && this._isClickDisabled(el)) {
              return;
            }
            var type = e.type;
            if (type === "mousedown") {
              preventOutline(el);
            }
            this._fireDOMEvent(e, type);
          },
          _mouseEvents: ["click", "dblclick", "mouseover", "mouseout", "contextmenu"],
          _fireDOMEvent: function(e, type, canvasTargets) {
            if (e.type === "click") {
              var synth = extend({}, e);
              synth.type = "preclick";
              this._fireDOMEvent(synth, synth.type, canvasTargets);
            }
            var targets = this._findEventTargets(e, type);
            if (canvasTargets) {
              var filtered = [];
              for (var i = 0; i < canvasTargets.length; i++) {
                if (canvasTargets[i].listens(type, true)) {
                  filtered.push(canvasTargets[i]);
                }
              }
              targets = filtered.concat(targets);
            }
            if (!targets.length) {
              return;
            }
            if (type === "contextmenu") {
              preventDefault(e);
            }
            var target = targets[0];
            var data = {
              originalEvent: e
            };
            if (e.type !== "keypress" && e.type !== "keydown" && e.type !== "keyup") {
              var isMarker = target.getLatLng && (!target._radius || target._radius <= 10);
              data.containerPoint = isMarker ? this.latLngToContainerPoint(target.getLatLng()) : this.mouseEventToContainerPoint(e);
              data.layerPoint = this.containerPointToLayerPoint(data.containerPoint);
              data.latlng = isMarker ? target.getLatLng() : this.layerPointToLatLng(data.layerPoint);
            }
            for (i = 0; i < targets.length; i++) {
              targets[i].fire(type, data, true);
              if (data.originalEvent._stopped || targets[i].options.bubblingMouseEvents === false && indexOf(this._mouseEvents, type) !== -1) {
                return;
              }
            }
          },
          _draggableMoved: function(obj) {
            obj = obj.dragging && obj.dragging.enabled() ? obj : this;
            return obj.dragging && obj.dragging.moved() || this.boxZoom && this.boxZoom.moved();
          },
          _clearHandlers: function() {
            for (var i = 0, len = this._handlers.length; i < len; i++) {
              this._handlers[i].disable();
            }
          },
          // @section Other Methods
          // @method whenReady(fn: Function, context?: Object): this
          // Runs the given function `fn` when the map gets initialized with
          // a view (center and zoom) and at least one layer, or immediately
          // if it's already initialized, optionally passing a function context.
          whenReady: function(callback, context) {
            if (this._loaded) {
              callback.call(context || this, { target: this });
            } else {
              this.on("load", callback, context);
            }
            return this;
          },
          // private methods for getting map state
          _getMapPanePos: function() {
            return getPosition(this._mapPane) || new Point(0, 0);
          },
          _moved: function() {
            var pos = this._getMapPanePos();
            return pos && !pos.equals([0, 0]);
          },
          _getTopLeftPoint: function(center, zoom2) {
            var pixelOrigin = center && zoom2 !== void 0 ? this._getNewPixelOrigin(center, zoom2) : this.getPixelOrigin();
            return pixelOrigin.subtract(this._getMapPanePos());
          },
          _getNewPixelOrigin: function(center, zoom2) {
            var viewHalf = this.getSize()._divideBy(2);
            return this.project(center, zoom2)._subtract(viewHalf)._add(this._getMapPanePos())._round();
          },
          _latLngToNewLayerPoint: function(latlng, zoom2, center) {
            var topLeft = this._getNewPixelOrigin(center, zoom2);
            return this.project(latlng, zoom2)._subtract(topLeft);
          },
          _latLngBoundsToNewLayerBounds: function(latLngBounds2, zoom2, center) {
            var topLeft = this._getNewPixelOrigin(center, zoom2);
            return toBounds([
              this.project(latLngBounds2.getSouthWest(), zoom2)._subtract(topLeft),
              this.project(latLngBounds2.getNorthWest(), zoom2)._subtract(topLeft),
              this.project(latLngBounds2.getSouthEast(), zoom2)._subtract(topLeft),
              this.project(latLngBounds2.getNorthEast(), zoom2)._subtract(topLeft)
            ]);
          },
          // layer point of the current center
          _getCenterLayerPoint: function() {
            return this.containerPointToLayerPoint(this.getSize()._divideBy(2));
          },
          // offset of the specified place to the current center in pixels
          _getCenterOffset: function(latlng) {
            return this.latLngToLayerPoint(latlng).subtract(this._getCenterLayerPoint());
          },
          // adjust center for view to get inside bounds
          _limitCenter: function(center, zoom2, bounds) {
            if (!bounds) {
              return center;
            }
            var centerPoint = this.project(center, zoom2), viewHalf = this.getSize().divideBy(2), viewBounds = new Bounds(centerPoint.subtract(viewHalf), centerPoint.add(viewHalf)), offset = this._getBoundsOffset(viewBounds, bounds, zoom2);
            if (Math.abs(offset.x) <= 1 && Math.abs(offset.y) <= 1) {
              return center;
            }
            return this.unproject(centerPoint.add(offset), zoom2);
          },
          // adjust offset for view to get inside bounds
          _limitOffset: function(offset, bounds) {
            if (!bounds) {
              return offset;
            }
            var viewBounds = this.getPixelBounds(), newBounds = new Bounds(viewBounds.min.add(offset), viewBounds.max.add(offset));
            return offset.add(this._getBoundsOffset(newBounds, bounds));
          },
          // returns offset needed for pxBounds to get inside maxBounds at a specified zoom
          _getBoundsOffset: function(pxBounds, maxBounds, zoom2) {
            var projectedMaxBounds = toBounds(
              this.project(maxBounds.getNorthEast(), zoom2),
              this.project(maxBounds.getSouthWest(), zoom2)
            ), minOffset = projectedMaxBounds.min.subtract(pxBounds.min), maxOffset = projectedMaxBounds.max.subtract(pxBounds.max), dx = this._rebound(minOffset.x, -maxOffset.x), dy = this._rebound(minOffset.y, -maxOffset.y);
            return new Point(dx, dy);
          },
          _rebound: function(left, right) {
            return left + right > 0 ? Math.round(left - right) / 2 : Math.max(0, Math.ceil(left)) - Math.max(0, Math.floor(right));
          },
          _limitZoom: function(zoom2) {
            var min = this.getMinZoom(), max = this.getMaxZoom(), snap = Browser.any3d ? this.options.zoomSnap : 1;
            if (snap) {
              zoom2 = Math.round(zoom2 / snap) * snap;
            }
            return Math.max(min, Math.min(max, zoom2));
          },
          _onPanTransitionStep: function() {
            this.fire("move");
          },
          _onPanTransitionEnd: function() {
            removeClass(this._mapPane, "leaflet-pan-anim");
            this.fire("moveend");
          },
          _tryAnimatedPan: function(center, options) {
            var offset = this._getCenterOffset(center)._trunc();
            if ((options && options.animate) !== true && !this.getSize().contains(offset)) {
              return false;
            }
            this.panBy(offset, options);
            return true;
          },
          _createAnimProxy: function() {
            var proxy = this._proxy = create$1("div", "leaflet-proxy leaflet-zoom-animated");
            this._panes.mapPane.appendChild(proxy);
            this.on("zoomanim", function(e) {
              var prop = TRANSFORM, transform = this._proxy.style[prop];
              setTransform(this._proxy, this.project(e.center, e.zoom), this.getZoomScale(e.zoom, 1));
              if (transform === this._proxy.style[prop] && this._animatingZoom) {
                this._onZoomTransitionEnd();
              }
            }, this);
            this.on("load moveend", this._animMoveEnd, this);
            this._on("unload", this._destroyAnimProxy, this);
          },
          _destroyAnimProxy: function() {
            remove(this._proxy);
            this.off("load moveend", this._animMoveEnd, this);
            delete this._proxy;
          },
          _animMoveEnd: function() {
            var c = this.getCenter(), z = this.getZoom();
            setTransform(this._proxy, this.project(c, z), this.getZoomScale(z, 1));
          },
          _catchTransitionEnd: function(e) {
            if (this._animatingZoom && e.propertyName.indexOf("transform") >= 0) {
              this._onZoomTransitionEnd();
            }
          },
          _nothingToAnimate: function() {
            return !this._container.getElementsByClassName("leaflet-zoom-animated").length;
          },
          _tryAnimatedZoom: function(center, zoom2, options) {
            if (this._animatingZoom) {
              return true;
            }
            options = options || {};
            if (!this._zoomAnimated || options.animate === false || this._nothingToAnimate() || Math.abs(zoom2 - this._zoom) > this.options.zoomAnimationThreshold) {
              return false;
            }
            var scale2 = this.getZoomScale(zoom2), offset = this._getCenterOffset(center)._divideBy(1 - 1 / scale2);
            if (options.animate !== true && !this.getSize().contains(offset)) {
              return false;
            }
            requestAnimFrame(function() {
              this._moveStart(true, options.noMoveStart || false)._animateZoom(center, zoom2, true);
            }, this);
            return true;
          },
          _animateZoom: function(center, zoom2, startAnim, noUpdate) {
            if (!this._mapPane) {
              return;
            }
            if (startAnim) {
              this._animatingZoom = true;
              this._animateToCenter = center;
              this._animateToZoom = zoom2;
              addClass(this._mapPane, "leaflet-zoom-anim");
            }
            this.fire("zoomanim", {
              center,
              zoom: zoom2,
              noUpdate
            });
            if (!this._tempFireZoomEvent) {
              this._tempFireZoomEvent = this._zoom !== this._animateToZoom;
            }
            this._move(this._animateToCenter, this._animateToZoom, void 0, true);
            setTimeout(bind(this._onZoomTransitionEnd, this), 250);
          },
          _onZoomTransitionEnd: function() {
            if (!this._animatingZoom) {
              return;
            }
            if (this._mapPane) {
              removeClass(this._mapPane, "leaflet-zoom-anim");
            }
            this._animatingZoom = false;
            this._move(this._animateToCenter, this._animateToZoom, void 0, true);
            if (this._tempFireZoomEvent) {
              this.fire("zoom");
            }
            delete this._tempFireZoomEvent;
            this.fire("move");
            this._moveEnd(true);
          }
        });
        function createMap(id, options) {
          return new Map2(id, options);
        }
        var Control = Class.extend({
          // @section
          // @aka Control Options
          options: {
            // @option position: String = 'topright'
            // The position of the control (one of the map corners). Possible values are `'topleft'`,
            // `'topright'`, `'bottomleft'` or `'bottomright'`
            position: "topright"
          },
          initialize: function(options) {
            setOptions(this, options);
          },
          /* @section
           * Classes extending L.Control will inherit the following methods:
           *
           * @method getPosition: string
           * Returns the position of the control.
           */
          getPosition: function() {
            return this.options.position;
          },
          // @method setPosition(position: string): this
          // Sets the position of the control.
          setPosition: function(position) {
            var map2 = this._map;
            if (map2) {
              map2.removeControl(this);
            }
            this.options.position = position;
            if (map2) {
              map2.addControl(this);
            }
            return this;
          },
          // @method getContainer: HTMLElement
          // Returns the HTMLElement that contains the control.
          getContainer: function() {
            return this._container;
          },
          // @method addTo(map: Map): this
          // Adds the control to the given map.
          addTo: function(map2) {
            this.remove();
            this._map = map2;
            var container = this._container = this.onAdd(map2), pos = this.getPosition(), corner = map2._controlCorners[pos];
            addClass(container, "leaflet-control");
            if (pos.indexOf("bottom") !== -1) {
              corner.insertBefore(container, corner.firstChild);
            } else {
              corner.appendChild(container);
            }
            this._map.on("unload", this.remove, this);
            return this;
          },
          // @method remove: this
          // Removes the control from the map it is currently active on.
          remove: function() {
            if (!this._map) {
              return this;
            }
            remove(this._container);
            if (this.onRemove) {
              this.onRemove(this._map);
            }
            this._map.off("unload", this.remove, this);
            this._map = null;
            return this;
          },
          _refocusOnMap: function(e) {
            if (this._map && e && e.screenX > 0 && e.screenY > 0) {
              this._map.getContainer().focus();
            }
          }
        });
        var control = function(options) {
          return new Control(options);
        };
        Map2.include({
          // @method addControl(control: Control): this
          // Adds the given control to the map
          addControl: function(control2) {
            control2.addTo(this);
            return this;
          },
          // @method removeControl(control: Control): this
          // Removes the given control from the map
          removeControl: function(control2) {
            control2.remove();
            return this;
          },
          _initControlPos: function() {
            var corners = this._controlCorners = {}, l = "leaflet-", container = this._controlContainer = create$1("div", l + "control-container", this._container);
            function createCorner(vSide, hSide) {
              var className = l + vSide + " " + l + hSide;
              corners[vSide + hSide] = create$1("div", className, container);
            }
            createCorner("top", "left");
            createCorner("top", "right");
            createCorner("bottom", "left");
            createCorner("bottom", "right");
          },
          _clearControlPos: function() {
            for (var i in this._controlCorners) {
              remove(this._controlCorners[i]);
            }
            remove(this._controlContainer);
            delete this._controlCorners;
            delete this._controlContainer;
          }
        });
        var Layers = Control.extend({
          // @section
          // @aka Control.Layers options
          options: {
            // @option collapsed: Boolean = true
            // If `true`, the control will be collapsed into an icon and expanded on mouse hover, touch, or keyboard activation.
            collapsed: true,
            position: "topright",
            // @option autoZIndex: Boolean = true
            // If `true`, the control will assign zIndexes in increasing order to all of its layers so that the order is preserved when switching them on/off.
            autoZIndex: true,
            // @option hideSingleBase: Boolean = false
            // If `true`, the base layers in the control will be hidden when there is only one.
            hideSingleBase: false,
            // @option sortLayers: Boolean = false
            // Whether to sort the layers. When `false`, layers will keep the order
            // in which they were added to the control.
            sortLayers: false,
            // @option sortFunction: Function = *
            // A [compare function](https://developer.mozilla.org/docs/Web/JavaScript/Reference/Global_Objects/Array/sort)
            // that will be used for sorting the layers, when `sortLayers` is `true`.
            // The function receives both the `L.Layer` instances and their names, as in
            // `sortFunction(layerA, layerB, nameA, nameB)`.
            // By default, it sorts layers alphabetically by their name.
            sortFunction: function(layerA, layerB, nameA, nameB) {
              return nameA < nameB ? -1 : nameB < nameA ? 1 : 0;
            }
          },
          initialize: function(baseLayers, overlays, options) {
            setOptions(this, options);
            this._layerControlInputs = [];
            this._layers = [];
            this._lastZIndex = 0;
            this._handlingClick = false;
            this._preventClick = false;
            for (var i in baseLayers) {
              this._addLayer(baseLayers[i], i);
            }
            for (i in overlays) {
              this._addLayer(overlays[i], i, true);
            }
          },
          onAdd: function(map2) {
            this._initLayout();
            this._update();
            this._map = map2;
            map2.on("zoomend", this._checkDisabledLayers, this);
            for (var i = 0; i < this._layers.length; i++) {
              this._layers[i].layer.on("add remove", this._onLayerChange, this);
            }
            return this._container;
          },
          addTo: function(map2) {
            Control.prototype.addTo.call(this, map2);
            return this._expandIfNotCollapsed();
          },
          onRemove: function() {
            this._map.off("zoomend", this._checkDisabledLayers, this);
            for (var i = 0; i < this._layers.length; i++) {
              this._layers[i].layer.off("add remove", this._onLayerChange, this);
            }
          },
          // @method addBaseLayer(layer: Layer, name: String): this
          // Adds a base layer (radio button entry) with the given name to the control.
          addBaseLayer: function(layer, name) {
            this._addLayer(layer, name);
            return this._map ? this._update() : this;
          },
          // @method addOverlay(layer: Layer, name: String): this
          // Adds an overlay (checkbox entry) with the given name to the control.
          addOverlay: function(layer, name) {
            this._addLayer(layer, name, true);
            return this._map ? this._update() : this;
          },
          // @method removeLayer(layer: Layer): this
          // Remove the given layer from the control.
          removeLayer: function(layer) {
            layer.off("add remove", this._onLayerChange, this);
            var obj = this._getLayer(stamp(layer));
            if (obj) {
              this._layers.splice(this._layers.indexOf(obj), 1);
            }
            return this._map ? this._update() : this;
          },
          // @method expand(): this
          // Expand the control container if collapsed.
          expand: function() {
            addClass(this._container, "leaflet-control-layers-expanded");
            this._section.style.height = null;
            var acceptableHeight = this._map.getSize().y - (this._container.offsetTop + 50);
            if (acceptableHeight < this._section.clientHeight) {
              addClass(this._section, "leaflet-control-layers-scrollbar");
              this._section.style.height = acceptableHeight + "px";
            } else {
              removeClass(this._section, "leaflet-control-layers-scrollbar");
            }
            this._checkDisabledLayers();
            return this;
          },
          // @method collapse(): this
          // Collapse the control container if expanded.
          collapse: function() {
            removeClass(this._container, "leaflet-control-layers-expanded");
            return this;
          },
          _initLayout: function() {
            var className = "leaflet-control-layers", container = this._container = create$1("div", className), collapsed = this.options.collapsed;
            container.setAttribute("aria-haspopup", true);
            disableClickPropagation(container);
            disableScrollPropagation(container);
            var section = this._section = create$1("section", className + "-list");
            if (collapsed) {
              this._map.on("click", this.collapse, this);
              on(container, {
                mouseenter: this._expandSafely,
                mouseleave: this.collapse
              }, this);
            }
            var link = this._layersLink = create$1("a", className + "-toggle", container);
            link.href = "#";
            link.title = "Layers";
            link.setAttribute("role", "button");
            on(link, {
              keydown: function(e) {
                if (e.keyCode === 13) {
                  this._expandSafely();
                }
              },
              // Certain screen readers intercept the key event and instead send a click event
              click: function(e) {
                preventDefault(e);
                this._expandSafely();
              }
            }, this);
            if (!collapsed) {
              this.expand();
            }
            this._baseLayersList = create$1("div", className + "-base", section);
            this._separator = create$1("div", className + "-separator", section);
            this._overlaysList = create$1("div", className + "-overlays", section);
            container.appendChild(section);
          },
          _getLayer: function(id) {
            for (var i = 0; i < this._layers.length; i++) {
              if (this._layers[i] && stamp(this._layers[i].layer) === id) {
                return this._layers[i];
              }
            }
          },
          _addLayer: function(layer, name, overlay) {
            if (this._map) {
              layer.on("add remove", this._onLayerChange, this);
            }
            this._layers.push({
              layer,
              name,
              overlay
            });
            if (this.options.sortLayers) {
              this._layers.sort(bind(function(a, b) {
                return this.options.sortFunction(a.layer, b.layer, a.name, b.name);
              }, this));
            }
            if (this.options.autoZIndex && layer.setZIndex) {
              this._lastZIndex++;
              layer.setZIndex(this._lastZIndex);
            }
            this._expandIfNotCollapsed();
          },
          _update: function() {
            if (!this._container) {
              return this;
            }
            empty(this._baseLayersList);
            empty(this._overlaysList);
            this._layerControlInputs = [];
            var baseLayersPresent, overlaysPresent, i, obj, baseLayersCount = 0;
            for (i = 0; i < this._layers.length; i++) {
              obj = this._layers[i];
              this._addItem(obj);
              overlaysPresent = overlaysPresent || obj.overlay;
              baseLayersPresent = baseLayersPresent || !obj.overlay;
              baseLayersCount += !obj.overlay ? 1 : 0;
            }
            if (this.options.hideSingleBase) {
              baseLayersPresent = baseLayersPresent && baseLayersCount > 1;
              this._baseLayersList.style.display = baseLayersPresent ? "" : "none";
            }
            this._separator.style.display = overlaysPresent && baseLayersPresent ? "" : "none";
            return this;
          },
          _onLayerChange: function(e) {
            if (!this._handlingClick) {
              this._update();
            }
            var obj = this._getLayer(stamp(e.target));
            var type = obj.overlay ? e.type === "add" ? "overlayadd" : "overlayremove" : e.type === "add" ? "baselayerchange" : null;
            if (type) {
              this._map.fire(type, obj);
            }
          },
          // IE7 bugs out if you create a radio dynamically, so you have to do it this hacky way (see https://stackoverflow.com/a/119079)
          _createRadioElement: function(name, checked) {
            var radioHtml = '<input type="radio" class="leaflet-control-layers-selector" name="' + name + '"' + (checked ? ' checked="checked"' : "") + "/>";
            var radioFragment = document.createElement("div");
            radioFragment.innerHTML = radioHtml;
            return radioFragment.firstChild;
          },
          _addItem: function(obj) {
            var label = document.createElement("label"), checked = this._map.hasLayer(obj.layer), input;
            if (obj.overlay) {
              input = document.createElement("input");
              input.type = "checkbox";
              input.className = "leaflet-control-layers-selector";
              input.defaultChecked = checked;
            } else {
              input = this._createRadioElement("leaflet-base-layers_" + stamp(this), checked);
            }
            this._layerControlInputs.push(input);
            input.layerId = stamp(obj.layer);
            on(input, "click", this._onInputClick, this);
            var name = document.createElement("span");
            name.innerHTML = " " + obj.name;
            var holder = document.createElement("span");
            label.appendChild(holder);
            holder.appendChild(input);
            holder.appendChild(name);
            var container = obj.overlay ? this._overlaysList : this._baseLayersList;
            container.appendChild(label);
            this._checkDisabledLayers();
            return label;
          },
          _onInputClick: function() {
            if (this._preventClick) {
              return;
            }
            var inputs = this._layerControlInputs, input, layer;
            var addedLayers = [], removedLayers = [];
            this._handlingClick = true;
            for (var i = inputs.length - 1; i >= 0; i--) {
              input = inputs[i];
              layer = this._getLayer(input.layerId).layer;
              if (input.checked) {
                addedLayers.push(layer);
              } else if (!input.checked) {
                removedLayers.push(layer);
              }
            }
            for (i = 0; i < removedLayers.length; i++) {
              if (this._map.hasLayer(removedLayers[i])) {
                this._map.removeLayer(removedLayers[i]);
              }
            }
            for (i = 0; i < addedLayers.length; i++) {
              if (!this._map.hasLayer(addedLayers[i])) {
                this._map.addLayer(addedLayers[i]);
              }
            }
            this._handlingClick = false;
            this._refocusOnMap();
          },
          _checkDisabledLayers: function() {
            var inputs = this._layerControlInputs, input, layer, zoom2 = this._map.getZoom();
            for (var i = inputs.length - 1; i >= 0; i--) {
              input = inputs[i];
              layer = this._getLayer(input.layerId).layer;
              input.disabled = layer.options.minZoom !== void 0 && zoom2 < layer.options.minZoom || layer.options.maxZoom !== void 0 && zoom2 > layer.options.maxZoom;
            }
          },
          _expandIfNotCollapsed: function() {
            if (this._map && !this.options.collapsed) {
              this.expand();
            }
            return this;
          },
          _expandSafely: function() {
            var section = this._section;
            this._preventClick = true;
            on(section, "click", preventDefault);
            this.expand();
            var that = this;
            setTimeout(function() {
              off(section, "click", preventDefault);
              that._preventClick = false;
            });
          }
        });
        var layers = function(baseLayers, overlays, options) {
          return new Layers(baseLayers, overlays, options);
        };
        var Zoom = Control.extend({
          // @section
          // @aka Control.Zoom options
          options: {
            position: "topleft",
            // @option zoomInText: String = '<span aria-hidden="true">+</span>'
            // The text set on the 'zoom in' button.
            zoomInText: '<span aria-hidden="true">+</span>',
            // @option zoomInTitle: String = 'Zoom in'
            // The title set on the 'zoom in' button.
            zoomInTitle: "Zoom in",
            // @option zoomOutText: String = '<span aria-hidden="true">&#x2212;</span>'
            // The text set on the 'zoom out' button.
            zoomOutText: '<span aria-hidden="true">&#x2212;</span>',
            // @option zoomOutTitle: String = 'Zoom out'
            // The title set on the 'zoom out' button.
            zoomOutTitle: "Zoom out"
          },
          onAdd: function(map2) {
            var zoomName = "leaflet-control-zoom", container = create$1("div", zoomName + " leaflet-bar"), options = this.options;
            this._zoomInButton = this._createButton(
              options.zoomInText,
              options.zoomInTitle,
              zoomName + "-in",
              container,
              this._zoomIn
            );
            this._zoomOutButton = this._createButton(
              options.zoomOutText,
              options.zoomOutTitle,
              zoomName + "-out",
              container,
              this._zoomOut
            );
            this._updateDisabled();
            map2.on("zoomend zoomlevelschange", this._updateDisabled, this);
            return container;
          },
          onRemove: function(map2) {
            map2.off("zoomend zoomlevelschange", this._updateDisabled, this);
          },
          disable: function() {
            this._disabled = true;
            this._updateDisabled();
            return this;
          },
          enable: function() {
            this._disabled = false;
            this._updateDisabled();
            return this;
          },
          _zoomIn: function(e) {
            if (!this._disabled && this._map._zoom < this._map.getMaxZoom()) {
              this._map.zoomIn(this._map.options.zoomDelta * (e.shiftKey ? 3 : 1));
            }
          },
          _zoomOut: function(e) {
            if (!this._disabled && this._map._zoom > this._map.getMinZoom()) {
              this._map.zoomOut(this._map.options.zoomDelta * (e.shiftKey ? 3 : 1));
            }
          },
          _createButton: function(html, title, className, container, fn) {
            var link = create$1("a", className, container);
            link.innerHTML = html;
            link.href = "#";
            link.title = title;
            link.setAttribute("role", "button");
            link.setAttribute("aria-label", title);
            disableClickPropagation(link);
            on(link, "click", stop);
            on(link, "click", fn, this);
            on(link, "click", this._refocusOnMap, this);
            return link;
          },
          _updateDisabled: function() {
            var map2 = this._map, className = "leaflet-disabled";
            removeClass(this._zoomInButton, className);
            removeClass(this._zoomOutButton, className);
            this._zoomInButton.setAttribute("aria-disabled", "false");
            this._zoomOutButton.setAttribute("aria-disabled", "false");
            if (this._disabled || map2._zoom === map2.getMinZoom()) {
              addClass(this._zoomOutButton, className);
              this._zoomOutButton.setAttribute("aria-disabled", "true");
            }
            if (this._disabled || map2._zoom === map2.getMaxZoom()) {
              addClass(this._zoomInButton, className);
              this._zoomInButton.setAttribute("aria-disabled", "true");
            }
          }
        });
        Map2.mergeOptions({
          zoomControl: true
        });
        Map2.addInitHook(function() {
          if (this.options.zoomControl) {
            this.zoomControl = new Zoom();
            this.addControl(this.zoomControl);
          }
        });
        var zoom = function(options) {
          return new Zoom(options);
        };
        var Scale = Control.extend({
          // @section
          // @aka Control.Scale options
          options: {
            position: "bottomleft",
            // @option maxWidth: Number = 100
            // Maximum width of the control in pixels. The width is set dynamically to show round values (e.g. 100, 200, 500).
            maxWidth: 100,
            // @option metric: Boolean = True
            // Whether to show the metric scale line (m/km).
            metric: true,
            // @option imperial: Boolean = True
            // Whether to show the imperial scale line (mi/ft).
            imperial: true
            // @option updateWhenIdle: Boolean = false
            // If `true`, the control is updated on [`moveend`](#map-moveend), otherwise it's always up-to-date (updated on [`move`](#map-move)).
          },
          onAdd: function(map2) {
            var className = "leaflet-control-scale", container = create$1("div", className), options = this.options;
            this._addScales(options, className + "-line", container);
            map2.on(options.updateWhenIdle ? "moveend" : "move", this._update, this);
            map2.whenReady(this._update, this);
            return container;
          },
          onRemove: function(map2) {
            map2.off(this.options.updateWhenIdle ? "moveend" : "move", this._update, this);
          },
          _addScales: function(options, className, container) {
            if (options.metric) {
              this._mScale = create$1("div", className, container);
            }
            if (options.imperial) {
              this._iScale = create$1("div", className, container);
            }
          },
          _update: function() {
            var map2 = this._map, y = map2.getSize().y / 2;
            var maxMeters = map2.distance(
              map2.containerPointToLatLng([0, y]),
              map2.containerPointToLatLng([this.options.maxWidth, y])
            );
            this._updateScales(maxMeters);
          },
          _updateScales: function(maxMeters) {
            if (this.options.metric && maxMeters) {
              this._updateMetric(maxMeters);
            }
            if (this.options.imperial && maxMeters) {
              this._updateImperial(maxMeters);
            }
          },
          _updateMetric: function(maxMeters) {
            var meters = this._getRoundNum(maxMeters), label = meters < 1e3 ? meters + " m" : meters / 1e3 + " km";
            this._updateScale(this._mScale, label, meters / maxMeters);
          },
          _updateImperial: function(maxMeters) {
            var maxFeet = maxMeters * 3.2808399, maxMiles, miles, feet;
            if (maxFeet > 5280) {
              maxMiles = maxFeet / 5280;
              miles = this._getRoundNum(maxMiles);
              this._updateScale(this._iScale, miles + " mi", miles / maxMiles);
            } else {
              feet = this._getRoundNum(maxFeet);
              this._updateScale(this._iScale, feet + " ft", feet / maxFeet);
            }
          },
          _updateScale: function(scale2, text, ratio) {
            scale2.style.width = Math.round(this.options.maxWidth * ratio) + "px";
            scale2.innerHTML = text;
          },
          _getRoundNum: function(num) {
            var pow10 = Math.pow(10, (Math.floor(num) + "").length - 1), d = num / pow10;
            d = d >= 10 ? 10 : d >= 5 ? 5 : d >= 3 ? 3 : d >= 2 ? 2 : 1;
            return pow10 * d;
          }
        });
        var scale = function(options) {
          return new Scale(options);
        };
        var ukrainianFlag = '<svg aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="12" height="8" viewBox="0 0 12 8" class="leaflet-attribution-flag"><path fill="#4C7BE1" d="M0 0h12v4H0z"/><path fill="#FFD500" d="M0 4h12v3H0z"/><path fill="#E0BC00" d="M0 7h12v1H0z"/></svg>';
        var Attribution = Control.extend({
          // @section
          // @aka Control.Attribution options
          options: {
            position: "bottomright",
            // @option prefix: String|false = 'Leaflet'
            // The HTML text shown before the attributions. Pass `false` to disable.
            prefix: '<a href="https://leafletjs.com" title="A JavaScript library for interactive maps">' + (Browser.inlineSvg ? ukrainianFlag + " " : "") + "Leaflet</a>"
          },
          initialize: function(options) {
            setOptions(this, options);
            this._attributions = {};
          },
          onAdd: function(map2) {
            map2.attributionControl = this;
            this._container = create$1("div", "leaflet-control-attribution");
            disableClickPropagation(this._container);
            for (var i in map2._layers) {
              if (map2._layers[i].getAttribution) {
                this.addAttribution(map2._layers[i].getAttribution());
              }
            }
            this._update();
            map2.on("layeradd", this._addAttribution, this);
            return this._container;
          },
          onRemove: function(map2) {
            map2.off("layeradd", this._addAttribution, this);
          },
          _addAttribution: function(ev) {
            if (ev.layer.getAttribution) {
              this.addAttribution(ev.layer.getAttribution());
              ev.layer.once("remove", function() {
                this.removeAttribution(ev.layer.getAttribution());
              }, this);
            }
          },
          // @method setPrefix(prefix: String|false): this
          // The HTML text shown before the attributions. Pass `false` to disable.
          setPrefix: function(prefix) {
            this.options.prefix = prefix;
            this._update();
            return this;
          },
          // @method addAttribution(text: String): this
          // Adds an attribution text (e.g. `'&copy; OpenStreetMap contributors'`).
          addAttribution: function(text) {
            if (!text) {
              return this;
            }
            if (!this._attributions[text]) {
              this._attributions[text] = 0;
            }
            this._attributions[text]++;
            this._update();
            return this;
          },
          // @method removeAttribution(text: String): this
          // Removes an attribution text.
          removeAttribution: function(text) {
            if (!text) {
              return this;
            }
            if (this._attributions[text]) {
              this._attributions[text]--;
              this._update();
            }
            return this;
          },
          _update: function() {
            if (!this._map) {
              return;
            }
            var attribs = [];
            for (var i in this._attributions) {
              if (this._attributions[i]) {
                attribs.push(i);
              }
            }
            var prefixAndAttribs = [];
            if (this.options.prefix) {
              prefixAndAttribs.push(this.options.prefix);
            }
            if (attribs.length) {
              prefixAndAttribs.push(attribs.join(", "));
            }
            this._container.innerHTML = prefixAndAttribs.join(' <span aria-hidden="true">|</span> ');
          }
        });
        Map2.mergeOptions({
          attributionControl: true
        });
        Map2.addInitHook(function() {
          if (this.options.attributionControl) {
            new Attribution().addTo(this);
          }
        });
        var attribution = function(options) {
          return new Attribution(options);
        };
        Control.Layers = Layers;
        Control.Zoom = Zoom;
        Control.Scale = Scale;
        Control.Attribution = Attribution;
        control.layers = layers;
        control.zoom = zoom;
        control.scale = scale;
        control.attribution = attribution;
        var Handler = Class.extend({
          initialize: function(map2) {
            this._map = map2;
          },
          // @method enable(): this
          // Enables the handler
          enable: function() {
            if (this._enabled) {
              return this;
            }
            this._enabled = true;
            this.addHooks();
            return this;
          },
          // @method disable(): this
          // Disables the handler
          disable: function() {
            if (!this._enabled) {
              return this;
            }
            this._enabled = false;
            this.removeHooks();
            return this;
          },
          // @method enabled(): Boolean
          // Returns `true` if the handler is enabled
          enabled: function() {
            return !!this._enabled;
          }
          // @section Extension methods
          // Classes inheriting from `Handler` must implement the two following methods:
          // @method addHooks()
          // Called when the handler is enabled, should add event hooks.
          // @method removeHooks()
          // Called when the handler is disabled, should remove the event hooks added previously.
        });
        Handler.addTo = function(map2, name) {
          map2.addHandler(name, this);
          return this;
        };
        var Mixin = { Events };
        var START = Browser.touch ? "touchstart mousedown" : "mousedown";
        var Draggable = Evented.extend({
          options: {
            // @section
            // @aka Draggable options
            // @option clickTolerance: Number = 3
            // The max number of pixels a user can shift the mouse pointer during a click
            // for it to be considered a valid click (as opposed to a mouse drag).
            clickTolerance: 3
          },
          // @constructor L.Draggable(el: HTMLElement, dragHandle?: HTMLElement, preventOutline?: Boolean, options?: Draggable options)
          // Creates a `Draggable` object for moving `el` when you start dragging the `dragHandle` element (equals `el` itself by default).
          initialize: function(element, dragStartTarget, preventOutline2, options) {
            setOptions(this, options);
            this._element = element;
            this._dragStartTarget = dragStartTarget || element;
            this._preventOutline = preventOutline2;
          },
          // @method enable()
          // Enables the dragging ability
          enable: function() {
            if (this._enabled) {
              return;
            }
            on(this._dragStartTarget, START, this._onDown, this);
            this._enabled = true;
          },
          // @method disable()
          // Disables the dragging ability
          disable: function() {
            if (!this._enabled) {
              return;
            }
            if (Draggable._dragging === this) {
              this.finishDrag(true);
            }
            off(this._dragStartTarget, START, this._onDown, this);
            this._enabled = false;
            this._moved = false;
          },
          _onDown: function(e) {
            if (!this._enabled) {
              return;
            }
            this._moved = false;
            if (hasClass(this._element, "leaflet-zoom-anim")) {
              return;
            }
            if (e.touches && e.touches.length !== 1) {
              if (Draggable._dragging === this) {
                this.finishDrag();
              }
              return;
            }
            if (Draggable._dragging || e.shiftKey || e.which !== 1 && e.button !== 1 && !e.touches) {
              return;
            }
            Draggable._dragging = this;
            if (this._preventOutline) {
              preventOutline(this._element);
            }
            disableImageDrag();
            disableTextSelection();
            if (this._moving) {
              return;
            }
            this.fire("down");
            var first = e.touches ? e.touches[0] : e, sizedParent = getSizedParentNode(this._element);
            this._startPoint = new Point(first.clientX, first.clientY);
            this._startPos = getPosition(this._element);
            this._parentScale = getScale(sizedParent);
            var mouseevent = e.type === "mousedown";
            on(document, mouseevent ? "mousemove" : "touchmove", this._onMove, this);
            on(document, mouseevent ? "mouseup" : "touchend touchcancel", this._onUp, this);
          },
          _onMove: function(e) {
            if (!this._enabled) {
              return;
            }
            if (e.touches && e.touches.length > 1) {
              this._moved = true;
              return;
            }
            var first = e.touches && e.touches.length === 1 ? e.touches[0] : e, offset = new Point(first.clientX, first.clientY)._subtract(this._startPoint);
            if (!offset.x && !offset.y) {
              return;
            }
            if (Math.abs(offset.x) + Math.abs(offset.y) < this.options.clickTolerance) {
              return;
            }
            offset.x /= this._parentScale.x;
            offset.y /= this._parentScale.y;
            preventDefault(e);
            if (!this._moved) {
              this.fire("dragstart");
              this._moved = true;
              addClass(document.body, "leaflet-dragging");
              this._lastTarget = e.target || e.srcElement;
              if (window.SVGElementInstance && this._lastTarget instanceof window.SVGElementInstance) {
                this._lastTarget = this._lastTarget.correspondingUseElement;
              }
              addClass(this._lastTarget, "leaflet-drag-target");
            }
            this._newPos = this._startPos.add(offset);
            this._moving = true;
            this._lastEvent = e;
            this._updatePosition();
          },
          _updatePosition: function() {
            var e = { originalEvent: this._lastEvent };
            this.fire("predrag", e);
            setPosition(this._element, this._newPos);
            this.fire("drag", e);
          },
          _onUp: function() {
            if (!this._enabled) {
              return;
            }
            this.finishDrag();
          },
          finishDrag: function(noInertia) {
            removeClass(document.body, "leaflet-dragging");
            if (this._lastTarget) {
              removeClass(this._lastTarget, "leaflet-drag-target");
              this._lastTarget = null;
            }
            off(document, "mousemove touchmove", this._onMove, this);
            off(document, "mouseup touchend touchcancel", this._onUp, this);
            enableImageDrag();
            enableTextSelection();
            var fireDragend = this._moved && this._moving;
            this._moving = false;
            Draggable._dragging = false;
            if (fireDragend) {
              this.fire("dragend", {
                noInertia,
                distance: this._newPos.distanceTo(this._startPos)
              });
            }
          }
        });
        function clipPolygon(points, bounds, round) {
          var clippedPoints, edges = [1, 4, 2, 8], i, j, k, a, b, len, edge2, p;
          for (i = 0, len = points.length; i < len; i++) {
            points[i]._code = _getBitCode(points[i], bounds);
          }
          for (k = 0; k < 4; k++) {
            edge2 = edges[k];
            clippedPoints = [];
            for (i = 0, len = points.length, j = len - 1; i < len; j = i++) {
              a = points[i];
              b = points[j];
              if (!(a._code & edge2)) {
                if (b._code & edge2) {
                  p = _getEdgeIntersection(b, a, edge2, bounds, round);
                  p._code = _getBitCode(p, bounds);
                  clippedPoints.push(p);
                }
                clippedPoints.push(a);
              } else if (!(b._code & edge2)) {
                p = _getEdgeIntersection(b, a, edge2, bounds, round);
                p._code = _getBitCode(p, bounds);
                clippedPoints.push(p);
              }
            }
            points = clippedPoints;
          }
          return points;
        }
        function polygonCenter(latlngs, crs) {
          var i, j, p1, p2, f, area, x, y, center;
          if (!latlngs || latlngs.length === 0) {
            throw new Error("latlngs not passed");
          }
          if (!isFlat(latlngs)) {
            console.warn("latlngs are not flat! Only the first ring will be used");
            latlngs = latlngs[0];
          }
          var centroidLatLng = toLatLng([0, 0]);
          var bounds = toLatLngBounds(latlngs);
          var areaBounds = bounds.getNorthWest().distanceTo(bounds.getSouthWest()) * bounds.getNorthEast().distanceTo(bounds.getNorthWest());
          if (areaBounds < 1700) {
            centroidLatLng = centroid(latlngs);
          }
          var len = latlngs.length;
          var points = [];
          for (i = 0; i < len; i++) {
            var latlng = toLatLng(latlngs[i]);
            points.push(crs.project(toLatLng([latlng.lat - centroidLatLng.lat, latlng.lng - centroidLatLng.lng])));
          }
          area = x = y = 0;
          for (i = 0, j = len - 1; i < len; j = i++) {
            p1 = points[i];
            p2 = points[j];
            f = p1.y * p2.x - p2.y * p1.x;
            x += (p1.x + p2.x) * f;
            y += (p1.y + p2.y) * f;
            area += f * 3;
          }
          if (area === 0) {
            center = points[0];
          } else {
            center = [x / area, y / area];
          }
          var latlngCenter = crs.unproject(toPoint(center));
          return toLatLng([latlngCenter.lat + centroidLatLng.lat, latlngCenter.lng + centroidLatLng.lng]);
        }
        function centroid(coords) {
          var latSum = 0;
          var lngSum = 0;
          var len = 0;
          for (var i = 0; i < coords.length; i++) {
            var latlng = toLatLng(coords[i]);
            latSum += latlng.lat;
            lngSum += latlng.lng;
            len++;
          }
          return toLatLng([latSum / len, lngSum / len]);
        }
        var PolyUtil = {
          __proto__: null,
          clipPolygon,
          polygonCenter,
          centroid
        };
        function simplify(points, tolerance) {
          if (!tolerance || !points.length) {
            return points.slice();
          }
          var sqTolerance = tolerance * tolerance;
          points = _reducePoints(points, sqTolerance);
          points = _simplifyDP(points, sqTolerance);
          return points;
        }
        function pointToSegmentDistance(p, p1, p2) {
          return Math.sqrt(_sqClosestPointOnSegment(p, p1, p2, true));
        }
        function closestPointOnSegment(p, p1, p2) {
          return _sqClosestPointOnSegment(p, p1, p2);
        }
        function _simplifyDP(points, sqTolerance) {
          var len = points.length, ArrayConstructor = typeof Uint8Array !== "undefined" ? Uint8Array : Array, markers = new ArrayConstructor(len);
          markers[0] = markers[len - 1] = 1;
          _simplifyDPStep(points, markers, sqTolerance, 0, len - 1);
          var i, newPoints = [];
          for (i = 0; i < len; i++) {
            if (markers[i]) {
              newPoints.push(points[i]);
            }
          }
          return newPoints;
        }
        function _simplifyDPStep(points, markers, sqTolerance, first, last) {
          var maxSqDist = 0, index2, i, sqDist;
          for (i = first + 1; i <= last - 1; i++) {
            sqDist = _sqClosestPointOnSegment(points[i], points[first], points[last], true);
            if (sqDist > maxSqDist) {
              index2 = i;
              maxSqDist = sqDist;
            }
          }
          if (maxSqDist > sqTolerance) {
            markers[index2] = 1;
            _simplifyDPStep(points, markers, sqTolerance, first, index2);
            _simplifyDPStep(points, markers, sqTolerance, index2, last);
          }
        }
        function _reducePoints(points, sqTolerance) {
          var reducedPoints = [points[0]];
          for (var i = 1, prev = 0, len = points.length; i < len; i++) {
            if (_sqDist(points[i], points[prev]) > sqTolerance) {
              reducedPoints.push(points[i]);
              prev = i;
            }
          }
          if (prev < len - 1) {
            reducedPoints.push(points[len - 1]);
          }
          return reducedPoints;
        }
        var _lastCode;
        function clipSegment(a, b, bounds, useLastCode, round) {
          var codeA = useLastCode ? _lastCode : _getBitCode(a, bounds), codeB = _getBitCode(b, bounds), codeOut, p, newCode;
          _lastCode = codeB;
          while (true) {
            if (!(codeA | codeB)) {
              return [a, b];
            }
            if (codeA & codeB) {
              return false;
            }
            codeOut = codeA || codeB;
            p = _getEdgeIntersection(a, b, codeOut, bounds, round);
            newCode = _getBitCode(p, bounds);
            if (codeOut === codeA) {
              a = p;
              codeA = newCode;
            } else {
              b = p;
              codeB = newCode;
            }
          }
        }
        function _getEdgeIntersection(a, b, code, bounds, round) {
          var dx = b.x - a.x, dy = b.y - a.y, min = bounds.min, max = bounds.max, x, y;
          if (code & 8) {
            x = a.x + dx * (max.y - a.y) / dy;
            y = max.y;
          } else if (code & 4) {
            x = a.x + dx * (min.y - a.y) / dy;
            y = min.y;
          } else if (code & 2) {
            x = max.x;
            y = a.y + dy * (max.x - a.x) / dx;
          } else if (code & 1) {
            x = min.x;
            y = a.y + dy * (min.x - a.x) / dx;
          }
          return new Point(x, y, round);
        }
        function _getBitCode(p, bounds) {
          var code = 0;
          if (p.x < bounds.min.x) {
            code |= 1;
          } else if (p.x > bounds.max.x) {
            code |= 2;
          }
          if (p.y < bounds.min.y) {
            code |= 4;
          } else if (p.y > bounds.max.y) {
            code |= 8;
          }
          return code;
        }
        function _sqDist(p1, p2) {
          var dx = p2.x - p1.x, dy = p2.y - p1.y;
          return dx * dx + dy * dy;
        }
        function _sqClosestPointOnSegment(p, p1, p2, sqDist) {
          var x = p1.x, y = p1.y, dx = p2.x - x, dy = p2.y - y, dot = dx * dx + dy * dy, t;
          if (dot > 0) {
            t = ((p.x - x) * dx + (p.y - y) * dy) / dot;
            if (t > 1) {
              x = p2.x;
              y = p2.y;
            } else if (t > 0) {
              x += dx * t;
              y += dy * t;
            }
          }
          dx = p.x - x;
          dy = p.y - y;
          return sqDist ? dx * dx + dy * dy : new Point(x, y);
        }
        function isFlat(latlngs) {
          return !isArray(latlngs[0]) || typeof latlngs[0][0] !== "object" && typeof latlngs[0][0] !== "undefined";
        }
        function _flat(latlngs) {
          console.warn("Deprecated use of _flat, please use L.LineUtil.isFlat instead.");
          return isFlat(latlngs);
        }
        function polylineCenter(latlngs, crs) {
          var i, halfDist, segDist, dist, p1, p2, ratio, center;
          if (!latlngs || latlngs.length === 0) {
            throw new Error("latlngs not passed");
          }
          if (!isFlat(latlngs)) {
            console.warn("latlngs are not flat! Only the first ring will be used");
            latlngs = latlngs[0];
          }
          var centroidLatLng = toLatLng([0, 0]);
          var bounds = toLatLngBounds(latlngs);
          var areaBounds = bounds.getNorthWest().distanceTo(bounds.getSouthWest()) * bounds.getNorthEast().distanceTo(bounds.getNorthWest());
          if (areaBounds < 1700) {
            centroidLatLng = centroid(latlngs);
          }
          var len = latlngs.length;
          var points = [];
          for (i = 0; i < len; i++) {
            var latlng = toLatLng(latlngs[i]);
            points.push(crs.project(toLatLng([latlng.lat - centroidLatLng.lat, latlng.lng - centroidLatLng.lng])));
          }
          for (i = 0, halfDist = 0; i < len - 1; i++) {
            halfDist += points[i].distanceTo(points[i + 1]) / 2;
          }
          if (halfDist === 0) {
            center = points[0];
          } else {
            for (i = 0, dist = 0; i < len - 1; i++) {
              p1 = points[i];
              p2 = points[i + 1];
              segDist = p1.distanceTo(p2);
              dist += segDist;
              if (dist > halfDist) {
                ratio = (dist - halfDist) / segDist;
                center = [
                  p2.x - ratio * (p2.x - p1.x),
                  p2.y - ratio * (p2.y - p1.y)
                ];
                break;
              }
            }
          }
          var latlngCenter = crs.unproject(toPoint(center));
          return toLatLng([latlngCenter.lat + centroidLatLng.lat, latlngCenter.lng + centroidLatLng.lng]);
        }
        var LineUtil = {
          __proto__: null,
          simplify,
          pointToSegmentDistance,
          closestPointOnSegment,
          clipSegment,
          _getEdgeIntersection,
          _getBitCode,
          _sqClosestPointOnSegment,
          isFlat,
          _flat,
          polylineCenter
        };
        var LonLat = {
          project: function(latlng) {
            return new Point(latlng.lng, latlng.lat);
          },
          unproject: function(point) {
            return new LatLng(point.y, point.x);
          },
          bounds: new Bounds([-180, -90], [180, 90])
        };
        var Mercator = {
          R: 6378137,
          R_MINOR: 6356752314245179e-9,
          bounds: new Bounds([-2003750834279e-5, -1549657073972e-5], [2003750834279e-5, 1876465623138e-5]),
          project: function(latlng) {
            var d = Math.PI / 180, r = this.R, y = latlng.lat * d, tmp = this.R_MINOR / r, e = Math.sqrt(1 - tmp * tmp), con = e * Math.sin(y);
            var ts = Math.tan(Math.PI / 4 - y / 2) / Math.pow((1 - con) / (1 + con), e / 2);
            y = -r * Math.log(Math.max(ts, 1e-10));
            return new Point(latlng.lng * d * r, y);
          },
          unproject: function(point) {
            var d = 180 / Math.PI, r = this.R, tmp = this.R_MINOR / r, e = Math.sqrt(1 - tmp * tmp), ts = Math.exp(-point.y / r), phi = Math.PI / 2 - 2 * Math.atan(ts);
            for (var i = 0, dphi = 0.1, con; i < 15 && Math.abs(dphi) > 1e-7; i++) {
              con = e * Math.sin(phi);
              con = Math.pow((1 - con) / (1 + con), e / 2);
              dphi = Math.PI / 2 - 2 * Math.atan(ts * con) - phi;
              phi += dphi;
            }
            return new LatLng(phi * d, point.x * d / r);
          }
        };
        var index = {
          __proto__: null,
          LonLat,
          Mercator,
          SphericalMercator
        };
        var EPSG3395 = extend({}, Earth, {
          code: "EPSG:3395",
          projection: Mercator,
          transformation: (function() {
            var scale2 = 0.5 / (Math.PI * Mercator.R);
            return toTransformation(scale2, 0.5, -scale2, 0.5);
          })()
        });
        var EPSG4326 = extend({}, Earth, {
          code: "EPSG:4326",
          projection: LonLat,
          transformation: toTransformation(1 / 180, 1, -1 / 180, 0.5)
        });
        var Simple = extend({}, CRS, {
          projection: LonLat,
          transformation: toTransformation(1, 0, -1, 0),
          scale: function(zoom2) {
            return Math.pow(2, zoom2);
          },
          zoom: function(scale2) {
            return Math.log(scale2) / Math.LN2;
          },
          distance: function(latlng1, latlng2) {
            var dx = latlng2.lng - latlng1.lng, dy = latlng2.lat - latlng1.lat;
            return Math.sqrt(dx * dx + dy * dy);
          },
          infinite: true
        });
        CRS.Earth = Earth;
        CRS.EPSG3395 = EPSG3395;
        CRS.EPSG3857 = EPSG3857;
        CRS.EPSG900913 = EPSG900913;
        CRS.EPSG4326 = EPSG4326;
        CRS.Simple = Simple;
        var Layer = Evented.extend({
          // Classes extending `L.Layer` will inherit the following options:
          options: {
            // @option pane: String = 'overlayPane'
            // By default the layer will be added to the map's [overlay pane](#map-overlaypane). Overriding this option will cause the layer to be placed on another pane by default.
            pane: "overlayPane",
            // @option attribution: String = null
            // String to be shown in the attribution control, e.g. "© OpenStreetMap contributors". It describes the layer data and is often a legal obligation towards copyright holders and tile providers.
            attribution: null,
            bubblingMouseEvents: true
          },
          /* @section
           * Classes extending `L.Layer` will inherit the following methods:
           *
           * @method addTo(map: Map|LayerGroup): this
           * Adds the layer to the given map or layer group.
           */
          addTo: function(map2) {
            map2.addLayer(this);
            return this;
          },
          // @method remove: this
          // Removes the layer from the map it is currently active on.
          remove: function() {
            return this.removeFrom(this._map || this._mapToAdd);
          },
          // @method removeFrom(map: Map): this
          // Removes the layer from the given map
          //
          // @alternative
          // @method removeFrom(group: LayerGroup): this
          // Removes the layer from the given `LayerGroup`
          removeFrom: function(obj) {
            if (obj) {
              obj.removeLayer(this);
            }
            return this;
          },
          // @method getPane(name? : String): HTMLElement
          // Returns the `HTMLElement` representing the named pane on the map. If `name` is omitted, returns the pane for this layer.
          getPane: function(name) {
            return this._map.getPane(name ? this.options[name] || name : this.options.pane);
          },
          addInteractiveTarget: function(targetEl) {
            this._map._targets[stamp(targetEl)] = this;
            return this;
          },
          removeInteractiveTarget: function(targetEl) {
            delete this._map._targets[stamp(targetEl)];
            return this;
          },
          // @method getAttribution: String
          // Used by the `attribution control`, returns the [attribution option](#gridlayer-attribution).
          getAttribution: function() {
            return this.options.attribution;
          },
          _layerAdd: function(e) {
            var map2 = e.target;
            if (!map2.hasLayer(this)) {
              return;
            }
            this._map = map2;
            this._zoomAnimated = map2._zoomAnimated;
            if (this.getEvents) {
              var events = this.getEvents();
              map2.on(events, this);
              this.once("remove", function() {
                map2.off(events, this);
              }, this);
            }
            this.onAdd(map2);
            this.fire("add");
            map2.fire("layeradd", { layer: this });
          }
        });
        Map2.include({
          // @method addLayer(layer: Layer): this
          // Adds the given layer to the map
          addLayer: function(layer) {
            if (!layer._layerAdd) {
              throw new Error("The provided object is not a Layer.");
            }
            var id = stamp(layer);
            if (this._layers[id]) {
              return this;
            }
            this._layers[id] = layer;
            layer._mapToAdd = this;
            if (layer.beforeAdd) {
              layer.beforeAdd(this);
            }
            this.whenReady(layer._layerAdd, layer);
            return this;
          },
          // @method removeLayer(layer: Layer): this
          // Removes the given layer from the map.
          removeLayer: function(layer) {
            var id = stamp(layer);
            if (!this._layers[id]) {
              return this;
            }
            if (this._loaded) {
              layer.onRemove(this);
            }
            delete this._layers[id];
            if (this._loaded) {
              this.fire("layerremove", { layer });
              layer.fire("remove");
            }
            layer._map = layer._mapToAdd = null;
            return this;
          },
          // @method hasLayer(layer: Layer): Boolean
          // Returns `true` if the given layer is currently added to the map
          hasLayer: function(layer) {
            return stamp(layer) in this._layers;
          },
          /* @method eachLayer(fn: Function, context?: Object): this
           * Iterates over the layers of the map, optionally specifying context of the iterator function.
           * ```
           * map.eachLayer(function(layer){
           *     layer.bindPopup('Hello');
           * });
           * ```
           */
          eachLayer: function(method, context) {
            for (var i in this._layers) {
              method.call(context, this._layers[i]);
            }
            return this;
          },
          _addLayers: function(layers2) {
            layers2 = layers2 ? isArray(layers2) ? layers2 : [layers2] : [];
            for (var i = 0, len = layers2.length; i < len; i++) {
              this.addLayer(layers2[i]);
            }
          },
          _addZoomLimit: function(layer) {
            if (!isNaN(layer.options.maxZoom) || !isNaN(layer.options.minZoom)) {
              this._zoomBoundLayers[stamp(layer)] = layer;
              this._updateZoomLevels();
            }
          },
          _removeZoomLimit: function(layer) {
            var id = stamp(layer);
            if (this._zoomBoundLayers[id]) {
              delete this._zoomBoundLayers[id];
              this._updateZoomLevels();
            }
          },
          _updateZoomLevels: function() {
            var minZoom = Infinity, maxZoom = -Infinity, oldZoomSpan = this._getZoomSpan();
            for (var i in this._zoomBoundLayers) {
              var options = this._zoomBoundLayers[i].options;
              minZoom = options.minZoom === void 0 ? minZoom : Math.min(minZoom, options.minZoom);
              maxZoom = options.maxZoom === void 0 ? maxZoom : Math.max(maxZoom, options.maxZoom);
            }
            this._layersMaxZoom = maxZoom === -Infinity ? void 0 : maxZoom;
            this._layersMinZoom = minZoom === Infinity ? void 0 : minZoom;
            if (oldZoomSpan !== this._getZoomSpan()) {
              this.fire("zoomlevelschange");
            }
            if (this.options.maxZoom === void 0 && this._layersMaxZoom && this.getZoom() > this._layersMaxZoom) {
              this.setZoom(this._layersMaxZoom);
            }
            if (this.options.minZoom === void 0 && this._layersMinZoom && this.getZoom() < this._layersMinZoom) {
              this.setZoom(this._layersMinZoom);
            }
          }
        });
        var LayerGroup = Layer.extend({
          initialize: function(layers2, options) {
            setOptions(this, options);
            this._layers = {};
            var i, len;
            if (layers2) {
              for (i = 0, len = layers2.length; i < len; i++) {
                this.addLayer(layers2[i]);
              }
            }
          },
          // @method addLayer(layer: Layer): this
          // Adds the given layer to the group.
          addLayer: function(layer) {
            var id = this.getLayerId(layer);
            this._layers[id] = layer;
            if (this._map) {
              this._map.addLayer(layer);
            }
            return this;
          },
          // @method removeLayer(layer: Layer): this
          // Removes the given layer from the group.
          // @alternative
          // @method removeLayer(id: Number): this
          // Removes the layer with the given internal ID from the group.
          removeLayer: function(layer) {
            var id = layer in this._layers ? layer : this.getLayerId(layer);
            if (this._map && this._layers[id]) {
              this._map.removeLayer(this._layers[id]);
            }
            delete this._layers[id];
            return this;
          },
          // @method hasLayer(layer: Layer): Boolean
          // Returns `true` if the given layer is currently added to the group.
          // @alternative
          // @method hasLayer(id: Number): Boolean
          // Returns `true` if the given internal ID is currently added to the group.
          hasLayer: function(layer) {
            var layerId = typeof layer === "number" ? layer : this.getLayerId(layer);
            return layerId in this._layers;
          },
          // @method clearLayers(): this
          // Removes all the layers from the group.
          clearLayers: function() {
            return this.eachLayer(this.removeLayer, this);
          },
          // @method invoke(methodName: String, …): this
          // Calls `methodName` on every layer contained in this group, passing any
          // additional parameters. Has no effect if the layers contained do not
          // implement `methodName`.
          invoke: function(methodName) {
            var args = Array.prototype.slice.call(arguments, 1), i, layer;
            for (i in this._layers) {
              layer = this._layers[i];
              if (layer[methodName]) {
                layer[methodName].apply(layer, args);
              }
            }
            return this;
          },
          onAdd: function(map2) {
            this.eachLayer(map2.addLayer, map2);
          },
          onRemove: function(map2) {
            this.eachLayer(map2.removeLayer, map2);
          },
          // @method eachLayer(fn: Function, context?: Object): this
          // Iterates over the layers of the group, optionally specifying context of the iterator function.
          // ```js
          // group.eachLayer(function (layer) {
          // 	layer.bindPopup('Hello');
          // });
          // ```
          eachLayer: function(method, context) {
            for (var i in this._layers) {
              method.call(context, this._layers[i]);
            }
            return this;
          },
          // @method getLayer(id: Number): Layer
          // Returns the layer with the given internal ID.
          getLayer: function(id) {
            return this._layers[id];
          },
          // @method getLayers(): Layer[]
          // Returns an array of all the layers added to the group.
          getLayers: function() {
            var layers2 = [];
            this.eachLayer(layers2.push, layers2);
            return layers2;
          },
          // @method setZIndex(zIndex: Number): this
          // Calls `setZIndex` on every layer contained in this group, passing the z-index.
          setZIndex: function(zIndex) {
            return this.invoke("setZIndex", zIndex);
          },
          // @method getLayerId(layer: Layer): Number
          // Returns the internal ID for a layer
          getLayerId: function(layer) {
            return stamp(layer);
          }
        });
        var layerGroup = function(layers2, options) {
          return new LayerGroup(layers2, options);
        };
        var FeatureGroup = LayerGroup.extend({
          addLayer: function(layer) {
            if (this.hasLayer(layer)) {
              return this;
            }
            layer.addEventParent(this);
            LayerGroup.prototype.addLayer.call(this, layer);
            return this.fire("layeradd", { layer });
          },
          removeLayer: function(layer) {
            if (!this.hasLayer(layer)) {
              return this;
            }
            if (layer in this._layers) {
              layer = this._layers[layer];
            }
            layer.removeEventParent(this);
            LayerGroup.prototype.removeLayer.call(this, layer);
            return this.fire("layerremove", { layer });
          },
          // @method setStyle(style: Path options): this
          // Sets the given path options to each layer of the group that has a `setStyle` method.
          setStyle: function(style2) {
            return this.invoke("setStyle", style2);
          },
          // @method bringToFront(): this
          // Brings the layer group to the top of all other layers
          bringToFront: function() {
            return this.invoke("bringToFront");
          },
          // @method bringToBack(): this
          // Brings the layer group to the back of all other layers
          bringToBack: function() {
            return this.invoke("bringToBack");
          },
          // @method getBounds(): LatLngBounds
          // Returns the LatLngBounds of the Feature Group (created from bounds and coordinates of its children).
          getBounds: function() {
            var bounds = new LatLngBounds();
            for (var id in this._layers) {
              var layer = this._layers[id];
              bounds.extend(layer.getBounds ? layer.getBounds() : layer.getLatLng());
            }
            return bounds;
          }
        });
        var featureGroup = function(layers2, options) {
          return new FeatureGroup(layers2, options);
        };
        var Icon = Class.extend({
          /* @section
           * @aka Icon options
           *
           * @option iconUrl: String = null
           * **(required)** The URL to the icon image (absolute or relative to your script path).
           *
           * @option iconRetinaUrl: String = null
           * The URL to a retina sized version of the icon image (absolute or relative to your
           * script path). Used for Retina screen devices.
           *
           * @option iconSize: Point = null
           * Size of the icon image in pixels.
           *
           * @option iconAnchor: Point = null
           * The coordinates of the "tip" of the icon (relative to its top left corner). The icon
           * will be aligned so that this point is at the marker's geographical location. Centered
           * by default if size is specified, also can be set in CSS with negative margins.
           *
           * @option popupAnchor: Point = [0, 0]
           * The coordinates of the point from which popups will "open", relative to the icon anchor.
           *
           * @option tooltipAnchor: Point = [0, 0]
           * The coordinates of the point from which tooltips will "open", relative to the icon anchor.
           *
           * @option shadowUrl: String = null
           * The URL to the icon shadow image. If not specified, no shadow image will be created.
           *
           * @option shadowRetinaUrl: String = null
           *
           * @option shadowSize: Point = null
           * Size of the shadow image in pixels.
           *
           * @option shadowAnchor: Point = null
           * The coordinates of the "tip" of the shadow (relative to its top left corner) (the same
           * as iconAnchor if not specified).
           *
           * @option className: String = ''
           * A custom class name to assign to both icon and shadow images. Empty by default.
           */
          options: {
            popupAnchor: [0, 0],
            tooltipAnchor: [0, 0],
            // @option crossOrigin: Boolean|String = false
            // Whether the crossOrigin attribute will be added to the tiles.
            // If a String is provided, all tiles will have their crossOrigin attribute set to the String provided. This is needed if you want to access tile pixel data.
            // Refer to [CORS Settings](https://developer.mozilla.org/en-US/docs/Web/HTML/CORS_settings_attributes) for valid String values.
            crossOrigin: false
          },
          initialize: function(options) {
            setOptions(this, options);
          },
          // @method createIcon(oldIcon?: HTMLElement): HTMLElement
          // Called internally when the icon has to be shown, returns a `<img>` HTML element
          // styled according to the options.
          createIcon: function(oldIcon) {
            return this._createIcon("icon", oldIcon);
          },
          // @method createShadow(oldIcon?: HTMLElement): HTMLElement
          // As `createIcon`, but for the shadow beneath it.
          createShadow: function(oldIcon) {
            return this._createIcon("shadow", oldIcon);
          },
          _createIcon: function(name, oldIcon) {
            var src = this._getIconUrl(name);
            if (!src) {
              if (name === "icon") {
                throw new Error("iconUrl not set in Icon options (see the docs).");
              }
              return null;
            }
            var img = this._createImg(src, oldIcon && oldIcon.tagName === "IMG" ? oldIcon : null);
            this._setIconStyles(img, name);
            if (this.options.crossOrigin || this.options.crossOrigin === "") {
              img.crossOrigin = this.options.crossOrigin === true ? "" : this.options.crossOrigin;
            }
            return img;
          },
          _setIconStyles: function(img, name) {
            var options = this.options;
            var sizeOption = options[name + "Size"];
            if (typeof sizeOption === "number") {
              sizeOption = [sizeOption, sizeOption];
            }
            var size = toPoint(sizeOption), anchor = toPoint(name === "shadow" && options.shadowAnchor || options.iconAnchor || size && size.divideBy(2, true));
            img.className = "leaflet-marker-" + name + " " + (options.className || "");
            if (anchor) {
              img.style.marginLeft = -anchor.x + "px";
              img.style.marginTop = -anchor.y + "px";
            }
            if (size) {
              img.style.width = size.x + "px";
              img.style.height = size.y + "px";
            }
          },
          _createImg: function(src, el) {
            el = el || document.createElement("img");
            el.src = src;
            return el;
          },
          _getIconUrl: function(name) {
            return Browser.retina && this.options[name + "RetinaUrl"] || this.options[name + "Url"];
          }
        });
        function icon(options) {
          return new Icon(options);
        }
        var IconDefault = Icon.extend({
          options: {
            iconUrl: "marker-icon.png",
            iconRetinaUrl: "marker-icon-2x.png",
            shadowUrl: "marker-shadow.png",
            iconSize: [25, 41],
            iconAnchor: [12, 41],
            popupAnchor: [1, -34],
            tooltipAnchor: [16, -28],
            shadowSize: [41, 41]
          },
          _getIconUrl: function(name) {
            if (typeof IconDefault.imagePath !== "string") {
              IconDefault.imagePath = this._detectIconPath();
            }
            return (this.options.imagePath || IconDefault.imagePath) + Icon.prototype._getIconUrl.call(this, name);
          },
          _stripUrl: function(path) {
            var strip = function(str, re, idx) {
              var match = re.exec(str);
              return match && match[idx];
            };
            path = strip(path, /^url\((['"])?(.+)\1\)$/, 2);
            return path && strip(path, /^(.*)marker-icon\.png$/, 1);
          },
          _detectIconPath: function() {
            var el = create$1("div", "leaflet-default-icon-path", document.body);
            var path = getStyle(el, "background-image") || getStyle(el, "backgroundImage");
            document.body.removeChild(el);
            path = this._stripUrl(path);
            if (path) {
              return path;
            }
            var link = document.querySelector('link[href$="leaflet.css"]');
            if (!link) {
              return "";
            }
            return link.href.substring(0, link.href.length - "leaflet.css".length - 1);
          }
        });
        var MarkerDrag = Handler.extend({
          initialize: function(marker2) {
            this._marker = marker2;
          },
          addHooks: function() {
            var icon2 = this._marker._icon;
            if (!this._draggable) {
              this._draggable = new Draggable(icon2, icon2, true);
            }
            this._draggable.on({
              dragstart: this._onDragStart,
              predrag: this._onPreDrag,
              drag: this._onDrag,
              dragend: this._onDragEnd
            }, this).enable();
            addClass(icon2, "leaflet-marker-draggable");
          },
          removeHooks: function() {
            this._draggable.off({
              dragstart: this._onDragStart,
              predrag: this._onPreDrag,
              drag: this._onDrag,
              dragend: this._onDragEnd
            }, this).disable();
            if (this._marker._icon) {
              removeClass(this._marker._icon, "leaflet-marker-draggable");
            }
          },
          moved: function() {
            return this._draggable && this._draggable._moved;
          },
          _adjustPan: function(e) {
            var marker2 = this._marker, map2 = marker2._map, speed = this._marker.options.autoPanSpeed, padding = this._marker.options.autoPanPadding, iconPos = getPosition(marker2._icon), bounds = map2.getPixelBounds(), origin = map2.getPixelOrigin();
            var panBounds = toBounds(
              bounds.min._subtract(origin).add(padding),
              bounds.max._subtract(origin).subtract(padding)
            );
            if (!panBounds.contains(iconPos)) {
              var movement = toPoint(
                (Math.max(panBounds.max.x, iconPos.x) - panBounds.max.x) / (bounds.max.x - panBounds.max.x) - (Math.min(panBounds.min.x, iconPos.x) - panBounds.min.x) / (bounds.min.x - panBounds.min.x),
                (Math.max(panBounds.max.y, iconPos.y) - panBounds.max.y) / (bounds.max.y - panBounds.max.y) - (Math.min(panBounds.min.y, iconPos.y) - panBounds.min.y) / (bounds.min.y - panBounds.min.y)
              ).multiplyBy(speed);
              map2.panBy(movement, { animate: false });
              this._draggable._newPos._add(movement);
              this._draggable._startPos._add(movement);
              setPosition(marker2._icon, this._draggable._newPos);
              this._onDrag(e);
              this._panRequest = requestAnimFrame(this._adjustPan.bind(this, e));
            }
          },
          _onDragStart: function() {
            this._oldLatLng = this._marker.getLatLng();
            this._marker.closePopup && this._marker.closePopup();
            this._marker.fire("movestart").fire("dragstart");
          },
          _onPreDrag: function(e) {
            if (this._marker.options.autoPan) {
              cancelAnimFrame(this._panRequest);
              this._panRequest = requestAnimFrame(this._adjustPan.bind(this, e));
            }
          },
          _onDrag: function(e) {
            var marker2 = this._marker, shadow = marker2._shadow, iconPos = getPosition(marker2._icon), latlng = marker2._map.layerPointToLatLng(iconPos);
            if (shadow) {
              setPosition(shadow, iconPos);
            }
            marker2._latlng = latlng;
            e.latlng = latlng;
            e.oldLatLng = this._oldLatLng;
            marker2.fire("move", e).fire("drag", e);
          },
          _onDragEnd: function(e) {
            cancelAnimFrame(this._panRequest);
            delete this._oldLatLng;
            this._marker.fire("moveend").fire("dragend", e);
          }
        });
        var Marker = Layer.extend({
          // @section
          // @aka Marker options
          options: {
            // @option icon: Icon = *
            // Icon instance to use for rendering the marker.
            // See [Icon documentation](#L.Icon) for details on how to customize the marker icon.
            // If not specified, a common instance of `L.Icon.Default` is used.
            icon: new IconDefault(),
            // Option inherited from "Interactive layer" abstract class
            interactive: true,
            // @option keyboard: Boolean = true
            // Whether the marker can be tabbed to with a keyboard and clicked by pressing enter.
            keyboard: true,
            // @option title: String = ''
            // Text for the browser tooltip that appear on marker hover (no tooltip by default).
            // [Useful for accessibility](https://leafletjs.com/examples/accessibility/#markers-must-be-labelled).
            title: "",
            // @option alt: String = 'Marker'
            // Text for the `alt` attribute of the icon image.
            // [Useful for accessibility](https://leafletjs.com/examples/accessibility/#markers-must-be-labelled).
            alt: "Marker",
            // @option zIndexOffset: Number = 0
            // By default, marker images zIndex is set automatically based on its latitude. Use this option if you want to put the marker on top of all others (or below), specifying a high value like `1000` (or high negative value, respectively).
            zIndexOffset: 0,
            // @option opacity: Number = 1.0
            // The opacity of the marker.
            opacity: 1,
            // @option riseOnHover: Boolean = false
            // If `true`, the marker will get on top of others when you hover the mouse over it.
            riseOnHover: false,
            // @option riseOffset: Number = 250
            // The z-index offset used for the `riseOnHover` feature.
            riseOffset: 250,
            // @option pane: String = 'markerPane'
            // `Map pane` where the markers icon will be added.
            pane: "markerPane",
            // @option shadowPane: String = 'shadowPane'
            // `Map pane` where the markers shadow will be added.
            shadowPane: "shadowPane",
            // @option bubblingMouseEvents: Boolean = false
            // When `true`, a mouse event on this marker will trigger the same event on the map
            // (unless [`L.DomEvent.stopPropagation`](#domevent-stoppropagation) is used).
            bubblingMouseEvents: false,
            // @option autoPanOnFocus: Boolean = true
            // When `true`, the map will pan whenever the marker is focused (via
            // e.g. pressing `tab` on the keyboard) to ensure the marker is
            // visible within the map's bounds
            autoPanOnFocus: true,
            // @section Draggable marker options
            // @option draggable: Boolean = false
            // Whether the marker is draggable with mouse/touch or not.
            draggable: false,
            // @option autoPan: Boolean = false
            // Whether to pan the map when dragging this marker near its edge or not.
            autoPan: false,
            // @option autoPanPadding: Point = Point(50, 50)
            // Distance (in pixels to the left/right and to the top/bottom) of the
            // map edge to start panning the map.
            autoPanPadding: [50, 50],
            // @option autoPanSpeed: Number = 10
            // Number of pixels the map should pan by.
            autoPanSpeed: 10
          },
          /* @section
           *
           * In addition to [shared layer methods](#Layer) like `addTo()` and `remove()` and [popup methods](#Popup) like bindPopup() you can also use the following methods:
           */
          initialize: function(latlng, options) {
            setOptions(this, options);
            this._latlng = toLatLng(latlng);
          },
          onAdd: function(map2) {
            this._zoomAnimated = this._zoomAnimated && map2.options.markerZoomAnimation;
            if (this._zoomAnimated) {
              map2.on("zoomanim", this._animateZoom, this);
            }
            this._initIcon();
            this.update();
          },
          onRemove: function(map2) {
            if (this.dragging && this.dragging.enabled()) {
              this.options.draggable = true;
              this.dragging.removeHooks();
            }
            delete this.dragging;
            if (this._zoomAnimated) {
              map2.off("zoomanim", this._animateZoom, this);
            }
            this._removeIcon();
            this._removeShadow();
          },
          getEvents: function() {
            return {
              zoom: this.update,
              viewreset: this.update
            };
          },
          // @method getLatLng: LatLng
          // Returns the current geographical position of the marker.
          getLatLng: function() {
            return this._latlng;
          },
          // @method setLatLng(latlng: LatLng): this
          // Changes the marker position to the given point.
          setLatLng: function(latlng) {
            var oldLatLng = this._latlng;
            this._latlng = toLatLng(latlng);
            this.update();
            return this.fire("move", { oldLatLng, latlng: this._latlng });
          },
          // @method setZIndexOffset(offset: Number): this
          // Changes the [zIndex offset](#marker-zindexoffset) of the marker.
          setZIndexOffset: function(offset) {
            this.options.zIndexOffset = offset;
            return this.update();
          },
          // @method getIcon: Icon
          // Returns the current icon used by the marker
          getIcon: function() {
            return this.options.icon;
          },
          // @method setIcon(icon: Icon): this
          // Changes the marker icon.
          setIcon: function(icon2) {
            this.options.icon = icon2;
            if (this._map) {
              this._initIcon();
              this.update();
            }
            if (this._popup) {
              this.bindPopup(this._popup, this._popup.options);
            }
            return this;
          },
          getElement: function() {
            return this._icon;
          },
          update: function() {
            if (this._icon && this._map) {
              var pos = this._map.latLngToLayerPoint(this._latlng).round();
              this._setPos(pos);
            }
            return this;
          },
          _initIcon: function() {
            var options = this.options, classToAdd = "leaflet-zoom-" + (this._zoomAnimated ? "animated" : "hide");
            var icon2 = options.icon.createIcon(this._icon), addIcon = false;
            if (icon2 !== this._icon) {
              if (this._icon) {
                this._removeIcon();
              }
              addIcon = true;
              if (options.title) {
                icon2.title = options.title;
              }
              if (icon2.tagName === "IMG") {
                icon2.alt = options.alt || "";
              }
            }
            addClass(icon2, classToAdd);
            if (options.keyboard) {
              icon2.tabIndex = "0";
              icon2.setAttribute("role", "button");
            }
            this._icon = icon2;
            if (options.riseOnHover) {
              this.on({
                mouseover: this._bringToFront,
                mouseout: this._resetZIndex
              });
            }
            if (this.options.autoPanOnFocus) {
              on(icon2, "focus", this._panOnFocus, this);
            }
            var newShadow = options.icon.createShadow(this._shadow), addShadow = false;
            if (newShadow !== this._shadow) {
              this._removeShadow();
              addShadow = true;
            }
            if (newShadow) {
              addClass(newShadow, classToAdd);
              newShadow.alt = "";
            }
            this._shadow = newShadow;
            if (options.opacity < 1) {
              this._updateOpacity();
            }
            if (addIcon) {
              this.getPane().appendChild(this._icon);
            }
            this._initInteraction();
            if (newShadow && addShadow) {
              this.getPane(options.shadowPane).appendChild(this._shadow);
            }
          },
          _removeIcon: function() {
            if (this.options.riseOnHover) {
              this.off({
                mouseover: this._bringToFront,
                mouseout: this._resetZIndex
              });
            }
            if (this.options.autoPanOnFocus) {
              off(this._icon, "focus", this._panOnFocus, this);
            }
            remove(this._icon);
            this.removeInteractiveTarget(this._icon);
            this._icon = null;
          },
          _removeShadow: function() {
            if (this._shadow) {
              remove(this._shadow);
            }
            this._shadow = null;
          },
          _setPos: function(pos) {
            if (this._icon) {
              setPosition(this._icon, pos);
            }
            if (this._shadow) {
              setPosition(this._shadow, pos);
            }
            this._zIndex = pos.y + this.options.zIndexOffset;
            this._resetZIndex();
          },
          _updateZIndex: function(offset) {
            if (this._icon) {
              this._icon.style.zIndex = this._zIndex + offset;
            }
          },
          _animateZoom: function(opt) {
            var pos = this._map._latLngToNewLayerPoint(this._latlng, opt.zoom, opt.center).round();
            this._setPos(pos);
          },
          _initInteraction: function() {
            if (!this.options.interactive) {
              return;
            }
            addClass(this._icon, "leaflet-interactive");
            this.addInteractiveTarget(this._icon);
            if (MarkerDrag) {
              var draggable = this.options.draggable;
              if (this.dragging) {
                draggable = this.dragging.enabled();
                this.dragging.disable();
              }
              this.dragging = new MarkerDrag(this);
              if (draggable) {
                this.dragging.enable();
              }
            }
          },
          // @method setOpacity(opacity: Number): this
          // Changes the opacity of the marker.
          setOpacity: function(opacity) {
            this.options.opacity = opacity;
            if (this._map) {
              this._updateOpacity();
            }
            return this;
          },
          _updateOpacity: function() {
            var opacity = this.options.opacity;
            if (this._icon) {
              setOpacity(this._icon, opacity);
            }
            if (this._shadow) {
              setOpacity(this._shadow, opacity);
            }
          },
          _bringToFront: function() {
            this._updateZIndex(this.options.riseOffset);
          },
          _resetZIndex: function() {
            this._updateZIndex(0);
          },
          _panOnFocus: function() {
            var map2 = this._map;
            if (!map2) {
              return;
            }
            var iconOpts = this.options.icon.options;
            var size = iconOpts.iconSize ? toPoint(iconOpts.iconSize) : toPoint(0, 0);
            var anchor = iconOpts.iconAnchor ? toPoint(iconOpts.iconAnchor) : toPoint(0, 0);
            map2.panInside(this._latlng, {
              paddingTopLeft: anchor,
              paddingBottomRight: size.subtract(anchor)
            });
          },
          _getPopupAnchor: function() {
            return this.options.icon.options.popupAnchor;
          },
          _getTooltipAnchor: function() {
            return this.options.icon.options.tooltipAnchor;
          }
        });
        function marker(latlng, options) {
          return new Marker(latlng, options);
        }
        var Path = Layer.extend({
          // @section
          // @aka Path options
          options: {
            // @option stroke: Boolean = true
            // Whether to draw stroke along the path. Set it to `false` to disable borders on polygons or circles.
            stroke: true,
            // @option color: String = '#3388ff'
            // Stroke color
            color: "#3388ff",
            // @option weight: Number = 3
            // Stroke width in pixels
            weight: 3,
            // @option opacity: Number = 1.0
            // Stroke opacity
            opacity: 1,
            // @option lineCap: String= 'round'
            // A string that defines [shape to be used at the end](https://developer.mozilla.org/docs/Web/SVG/Attribute/stroke-linecap) of the stroke.
            lineCap: "round",
            // @option lineJoin: String = 'round'
            // A string that defines [shape to be used at the corners](https://developer.mozilla.org/docs/Web/SVG/Attribute/stroke-linejoin) of the stroke.
            lineJoin: "round",
            // @option dashArray: String = null
            // A string that defines the stroke [dash pattern](https://developer.mozilla.org/docs/Web/SVG/Attribute/stroke-dasharray). Doesn't work on `Canvas`-powered layers in [some old browsers](https://developer.mozilla.org/docs/Web/API/CanvasRenderingContext2D/setLineDash#Browser_compatibility).
            dashArray: null,
            // @option dashOffset: String = null
            // A string that defines the [distance into the dash pattern to start the dash](https://developer.mozilla.org/docs/Web/SVG/Attribute/stroke-dashoffset). Doesn't work on `Canvas`-powered layers in [some old browsers](https://developer.mozilla.org/docs/Web/API/CanvasRenderingContext2D/setLineDash#Browser_compatibility).
            dashOffset: null,
            // @option fill: Boolean = depends
            // Whether to fill the path with color. Set it to `false` to disable filling on polygons or circles.
            fill: false,
            // @option fillColor: String = *
            // Fill color. Defaults to the value of the [`color`](#path-color) option
            fillColor: null,
            // @option fillOpacity: Number = 0.2
            // Fill opacity.
            fillOpacity: 0.2,
            // @option fillRule: String = 'evenodd'
            // A string that defines [how the inside of a shape](https://developer.mozilla.org/docs/Web/SVG/Attribute/fill-rule) is determined.
            fillRule: "evenodd",
            // className: '',
            // Option inherited from "Interactive layer" abstract class
            interactive: true,
            // @option bubblingMouseEvents: Boolean = true
            // When `true`, a mouse event on this path will trigger the same event on the map
            // (unless [`L.DomEvent.stopPropagation`](#domevent-stoppropagation) is used).
            bubblingMouseEvents: true
          },
          beforeAdd: function(map2) {
            this._renderer = map2.getRenderer(this);
          },
          onAdd: function() {
            this._renderer._initPath(this);
            this._reset();
            this._renderer._addPath(this);
          },
          onRemove: function() {
            this._renderer._removePath(this);
          },
          // @method redraw(): this
          // Redraws the layer. Sometimes useful after you changed the coordinates that the path uses.
          redraw: function() {
            if (this._map) {
              this._renderer._updatePath(this);
            }
            return this;
          },
          // @method setStyle(style: Path options): this
          // Changes the appearance of a Path based on the options in the `Path options` object.
          setStyle: function(style2) {
            setOptions(this, style2);
            if (this._renderer) {
              this._renderer._updateStyle(this);
              if (this.options.stroke && style2 && Object.prototype.hasOwnProperty.call(style2, "weight")) {
                this._updateBounds();
              }
            }
            return this;
          },
          // @method bringToFront(): this
          // Brings the layer to the top of all path layers.
          bringToFront: function() {
            if (this._renderer) {
              this._renderer._bringToFront(this);
            }
            return this;
          },
          // @method bringToBack(): this
          // Brings the layer to the bottom of all path layers.
          bringToBack: function() {
            if (this._renderer) {
              this._renderer._bringToBack(this);
            }
            return this;
          },
          getElement: function() {
            return this._path;
          },
          _reset: function() {
            this._project();
            this._update();
          },
          _clickTolerance: function() {
            return (this.options.stroke ? this.options.weight / 2 : 0) + (this._renderer.options.tolerance || 0);
          }
        });
        var CircleMarker = Path.extend({
          // @section
          // @aka CircleMarker options
          options: {
            fill: true,
            // @option radius: Number = 10
            // Radius of the circle marker, in pixels
            radius: 10
          },
          initialize: function(latlng, options) {
            setOptions(this, options);
            this._latlng = toLatLng(latlng);
            this._radius = this.options.radius;
          },
          // @method setLatLng(latLng: LatLng): this
          // Sets the position of a circle marker to a new location.
          setLatLng: function(latlng) {
            var oldLatLng = this._latlng;
            this._latlng = toLatLng(latlng);
            this.redraw();
            return this.fire("move", { oldLatLng, latlng: this._latlng });
          },
          // @method getLatLng(): LatLng
          // Returns the current geographical position of the circle marker
          getLatLng: function() {
            return this._latlng;
          },
          // @method setRadius(radius: Number): this
          // Sets the radius of a circle marker. Units are in pixels.
          setRadius: function(radius) {
            this.options.radius = this._radius = radius;
            return this.redraw();
          },
          // @method getRadius(): Number
          // Returns the current radius of the circle
          getRadius: function() {
            return this._radius;
          },
          setStyle: function(options) {
            var radius = options && options.radius || this._radius;
            Path.prototype.setStyle.call(this, options);
            this.setRadius(radius);
            return this;
          },
          _project: function() {
            this._point = this._map.latLngToLayerPoint(this._latlng);
            this._updateBounds();
          },
          _updateBounds: function() {
            var r = this._radius, r2 = this._radiusY || r, w = this._clickTolerance(), p = [r + w, r2 + w];
            this._pxBounds = new Bounds(this._point.subtract(p), this._point.add(p));
          },
          _update: function() {
            if (this._map) {
              this._updatePath();
            }
          },
          _updatePath: function() {
            this._renderer._updateCircle(this);
          },
          _empty: function() {
            return this._radius && !this._renderer._bounds.intersects(this._pxBounds);
          },
          // Needed by the `Canvas` renderer for interactivity
          _containsPoint: function(p) {
            return p.distanceTo(this._point) <= this._radius + this._clickTolerance();
          }
        });
        function circleMarker2(latlng, options) {
          return new CircleMarker(latlng, options);
        }
        var Circle = CircleMarker.extend({
          initialize: function(latlng, options, legacyOptions) {
            if (typeof options === "number") {
              options = extend({}, legacyOptions, { radius: options });
            }
            setOptions(this, options);
            this._latlng = toLatLng(latlng);
            if (isNaN(this.options.radius)) {
              throw new Error("Circle radius cannot be NaN");
            }
            this._mRadius = this.options.radius;
          },
          // @method setRadius(radius: Number): this
          // Sets the radius of a circle. Units are in meters.
          setRadius: function(radius) {
            this._mRadius = radius;
            return this.redraw();
          },
          // @method getRadius(): Number
          // Returns the current radius of a circle. Units are in meters.
          getRadius: function() {
            return this._mRadius;
          },
          // @method getBounds(): LatLngBounds
          // Returns the `LatLngBounds` of the path.
          getBounds: function() {
            var half = [this._radius, this._radiusY || this._radius];
            return new LatLngBounds(
              this._map.layerPointToLatLng(this._point.subtract(half)),
              this._map.layerPointToLatLng(this._point.add(half))
            );
          },
          setStyle: Path.prototype.setStyle,
          _project: function() {
            var lng = this._latlng.lng, lat = this._latlng.lat, map2 = this._map, crs = map2.options.crs;
            if (crs.distance === Earth.distance) {
              var d = Math.PI / 180, latR = this._mRadius / Earth.R / d, top = map2.project([lat + latR, lng]), bottom = map2.project([lat - latR, lng]), p = top.add(bottom).divideBy(2), lat2 = map2.unproject(p).lat, lngR = Math.acos((Math.cos(latR * d) - Math.sin(lat * d) * Math.sin(lat2 * d)) / (Math.cos(lat * d) * Math.cos(lat2 * d))) / d;
              if (isNaN(lngR) || lngR === 0) {
                lngR = latR / Math.cos(Math.PI / 180 * lat);
              }
              this._point = p.subtract(map2.getPixelOrigin());
              this._radius = isNaN(lngR) ? 0 : p.x - map2.project([lat2, lng - lngR]).x;
              this._radiusY = p.y - top.y;
            } else {
              var latlng2 = crs.unproject(crs.project(this._latlng).subtract([this._mRadius, 0]));
              this._point = map2.latLngToLayerPoint(this._latlng);
              this._radius = this._point.x - map2.latLngToLayerPoint(latlng2).x;
            }
            this._updateBounds();
          }
        });
        function circle(latlng, options, legacyOptions) {
          return new Circle(latlng, options, legacyOptions);
        }
        var Polyline = Path.extend({
          // @section
          // @aka Polyline options
          options: {
            // @option smoothFactor: Number = 1.0
            // How much to simplify the polyline on each zoom level. More means
            // better performance and smoother look, and less means more accurate representation.
            smoothFactor: 1,
            // @option noClip: Boolean = false
            // Disable polyline clipping.
            noClip: false
          },
          initialize: function(latlngs, options) {
            setOptions(this, options);
            this._setLatLngs(latlngs);
          },
          // @method getLatLngs(): LatLng[]
          // Returns an array of the points in the path, or nested arrays of points in case of multi-polyline.
          getLatLngs: function() {
            return this._latlngs;
          },
          // @method setLatLngs(latlngs: LatLng[]): this
          // Replaces all the points in the polyline with the given array of geographical points.
          setLatLngs: function(latlngs) {
            this._setLatLngs(latlngs);
            return this.redraw();
          },
          // @method isEmpty(): Boolean
          // Returns `true` if the Polyline has no LatLngs.
          isEmpty: function() {
            return !this._latlngs.length;
          },
          // @method closestLayerPoint(p: Point): Point
          // Returns the point closest to `p` on the Polyline.
          closestLayerPoint: function(p) {
            var minDistance = Infinity, minPoint = null, closest = _sqClosestPointOnSegment, p1, p2;
            for (var j = 0, jLen = this._parts.length; j < jLen; j++) {
              var points = this._parts[j];
              for (var i = 1, len = points.length; i < len; i++) {
                p1 = points[i - 1];
                p2 = points[i];
                var sqDist = closest(p, p1, p2, true);
                if (sqDist < minDistance) {
                  minDistance = sqDist;
                  minPoint = closest(p, p1, p2);
                }
              }
            }
            if (minPoint) {
              minPoint.distance = Math.sqrt(minDistance);
            }
            return minPoint;
          },
          // @method getCenter(): LatLng
          // Returns the center ([centroid](https://en.wikipedia.org/wiki/Centroid)) of the polyline.
          getCenter: function() {
            if (!this._map) {
              throw new Error("Must add layer to map before using getCenter()");
            }
            return polylineCenter(this._defaultShape(), this._map.options.crs);
          },
          // @method getBounds(): LatLngBounds
          // Returns the `LatLngBounds` of the path.
          getBounds: function() {
            return this._bounds;
          },
          // @method addLatLng(latlng: LatLng, latlngs?: LatLng[]): this
          // Adds a given point to the polyline. By default, adds to the first ring of
          // the polyline in case of a multi-polyline, but can be overridden by passing
          // a specific ring as a LatLng array (that you can earlier access with [`getLatLngs`](#polyline-getlatlngs)).
          addLatLng: function(latlng, latlngs) {
            latlngs = latlngs || this._defaultShape();
            latlng = toLatLng(latlng);
            latlngs.push(latlng);
            this._bounds.extend(latlng);
            return this.redraw();
          },
          _setLatLngs: function(latlngs) {
            this._bounds = new LatLngBounds();
            this._latlngs = this._convertLatLngs(latlngs);
          },
          _defaultShape: function() {
            return isFlat(this._latlngs) ? this._latlngs : this._latlngs[0];
          },
          // recursively convert latlngs input into actual LatLng instances; calculate bounds along the way
          _convertLatLngs: function(latlngs) {
            var result = [], flat = isFlat(latlngs);
            for (var i = 0, len = latlngs.length; i < len; i++) {
              if (flat) {
                result[i] = toLatLng(latlngs[i]);
                this._bounds.extend(result[i]);
              } else {
                result[i] = this._convertLatLngs(latlngs[i]);
              }
            }
            return result;
          },
          _project: function() {
            var pxBounds = new Bounds();
            this._rings = [];
            this._projectLatlngs(this._latlngs, this._rings, pxBounds);
            if (this._bounds.isValid() && pxBounds.isValid()) {
              this._rawPxBounds = pxBounds;
              this._updateBounds();
            }
          },
          _updateBounds: function() {
            var w = this._clickTolerance(), p = new Point(w, w);
            if (!this._rawPxBounds) {
              return;
            }
            this._pxBounds = new Bounds([
              this._rawPxBounds.min.subtract(p),
              this._rawPxBounds.max.add(p)
            ]);
          },
          // recursively turns latlngs into a set of rings with projected coordinates
          _projectLatlngs: function(latlngs, result, projectedBounds) {
            var flat = latlngs[0] instanceof LatLng, len = latlngs.length, i, ring;
            if (flat) {
              ring = [];
              for (i = 0; i < len; i++) {
                ring[i] = this._map.latLngToLayerPoint(latlngs[i]);
                projectedBounds.extend(ring[i]);
              }
              result.push(ring);
            } else {
              for (i = 0; i < len; i++) {
                this._projectLatlngs(latlngs[i], result, projectedBounds);
              }
            }
          },
          // clip polyline by renderer bounds so that we have less to render for performance
          _clipPoints: function() {
            var bounds = this._renderer._bounds;
            this._parts = [];
            if (!this._pxBounds || !this._pxBounds.intersects(bounds)) {
              return;
            }
            if (this.options.noClip) {
              this._parts = this._rings;
              return;
            }
            var parts = this._parts, i, j, k, len, len2, segment, points;
            for (i = 0, k = 0, len = this._rings.length; i < len; i++) {
              points = this._rings[i];
              for (j = 0, len2 = points.length; j < len2 - 1; j++) {
                segment = clipSegment(points[j], points[j + 1], bounds, j, true);
                if (!segment) {
                  continue;
                }
                parts[k] = parts[k] || [];
                parts[k].push(segment[0]);
                if (segment[1] !== points[j + 1] || j === len2 - 2) {
                  parts[k].push(segment[1]);
                  k++;
                }
              }
            }
          },
          // simplify each clipped part of the polyline for performance
          _simplifyPoints: function() {
            var parts = this._parts, tolerance = this.options.smoothFactor;
            for (var i = 0, len = parts.length; i < len; i++) {
              parts[i] = simplify(parts[i], tolerance);
            }
          },
          _update: function() {
            if (!this._map) {
              return;
            }
            this._clipPoints();
            this._simplifyPoints();
            this._updatePath();
          },
          _updatePath: function() {
            this._renderer._updatePoly(this);
          },
          // Needed by the `Canvas` renderer for interactivity
          _containsPoint: function(p, closed) {
            var i, j, k, len, len2, part, w = this._clickTolerance();
            if (!this._pxBounds || !this._pxBounds.contains(p)) {
              return false;
            }
            for (i = 0, len = this._parts.length; i < len; i++) {
              part = this._parts[i];
              for (j = 0, len2 = part.length, k = len2 - 1; j < len2; k = j++) {
                if (!closed && j === 0) {
                  continue;
                }
                if (pointToSegmentDistance(p, part[k], part[j]) <= w) {
                  return true;
                }
              }
            }
            return false;
          }
        });
        function polyline2(latlngs, options) {
          return new Polyline(latlngs, options);
        }
        Polyline._flat = _flat;
        var Polygon = Polyline.extend({
          options: {
            fill: true
          },
          isEmpty: function() {
            return !this._latlngs.length || !this._latlngs[0].length;
          },
          // @method getCenter(): LatLng
          // Returns the center ([centroid](http://en.wikipedia.org/wiki/Centroid)) of the Polygon.
          getCenter: function() {
            if (!this._map) {
              throw new Error("Must add layer to map before using getCenter()");
            }
            return polygonCenter(this._defaultShape(), this._map.options.crs);
          },
          _convertLatLngs: function(latlngs) {
            var result = Polyline.prototype._convertLatLngs.call(this, latlngs), len = result.length;
            if (len >= 2 && result[0] instanceof LatLng && result[0].equals(result[len - 1])) {
              result.pop();
            }
            return result;
          },
          _setLatLngs: function(latlngs) {
            Polyline.prototype._setLatLngs.call(this, latlngs);
            if (isFlat(this._latlngs)) {
              this._latlngs = [this._latlngs];
            }
          },
          _defaultShape: function() {
            return isFlat(this._latlngs[0]) ? this._latlngs[0] : this._latlngs[0][0];
          },
          _clipPoints: function() {
            var bounds = this._renderer._bounds, w = this.options.weight, p = new Point(w, w);
            bounds = new Bounds(bounds.min.subtract(p), bounds.max.add(p));
            this._parts = [];
            if (!this._pxBounds || !this._pxBounds.intersects(bounds)) {
              return;
            }
            if (this.options.noClip) {
              this._parts = this._rings;
              return;
            }
            for (var i = 0, len = this._rings.length, clipped; i < len; i++) {
              clipped = clipPolygon(this._rings[i], bounds, true);
              if (clipped.length) {
                this._parts.push(clipped);
              }
            }
          },
          _updatePath: function() {
            this._renderer._updatePoly(this, true);
          },
          // Needed by the `Canvas` renderer for interactivity
          _containsPoint: function(p) {
            var inside = false, part, p1, p2, i, j, k, len, len2;
            if (!this._pxBounds || !this._pxBounds.contains(p)) {
              return false;
            }
            for (i = 0, len = this._parts.length; i < len; i++) {
              part = this._parts[i];
              for (j = 0, len2 = part.length, k = len2 - 1; j < len2; k = j++) {
                p1 = part[j];
                p2 = part[k];
                if (p1.y > p.y !== p2.y > p.y && p.x < (p2.x - p1.x) * (p.y - p1.y) / (p2.y - p1.y) + p1.x) {
                  inside = !inside;
                }
              }
            }
            return inside || Polyline.prototype._containsPoint.call(this, p, true);
          }
        });
        function polygon(latlngs, options) {
          return new Polygon(latlngs, options);
        }
        var GeoJSON = FeatureGroup.extend({
          /* @section
           * @aka GeoJSON options
           *
           * @option pointToLayer: Function = *
           * A `Function` defining how GeoJSON points spawn Leaflet layers. It is internally
           * called when data is added, passing the GeoJSON point feature and its `LatLng`.
           * The default is to spawn a default `Marker`:
           * ```js
           * function(geoJsonPoint, latlng) {
           * 	return L.marker(latlng);
           * }
           * ```
           *
           * @option style: Function = *
           * A `Function` defining the `Path options` for styling GeoJSON lines and polygons,
           * called internally when data is added.
           * The default value is to not override any defaults:
           * ```js
           * function (geoJsonFeature) {
           * 	return {}
           * }
           * ```
           *
           * @option onEachFeature: Function = *
           * A `Function` that will be called once for each created `Feature`, after it has
           * been created and styled. Useful for attaching events and popups to features.
           * The default is to do nothing with the newly created layers:
           * ```js
           * function (feature, layer) {}
           * ```
           *
           * @option filter: Function = *
           * A `Function` that will be used to decide whether to include a feature or not.
           * The default is to include all features:
           * ```js
           * function (geoJsonFeature) {
           * 	return true;
           * }
           * ```
           * Note: dynamically changing the `filter` option will have effect only on newly
           * added data. It will _not_ re-evaluate already included features.
           *
           * @option coordsToLatLng: Function = *
           * A `Function` that will be used for converting GeoJSON coordinates to `LatLng`s.
           * The default is the `coordsToLatLng` static method.
           *
           * @option markersInheritOptions: Boolean = false
           * Whether default Markers for "Point" type Features inherit from group options.
           */
          initialize: function(geojson, options) {
            setOptions(this, options);
            this._layers = {};
            if (geojson) {
              this.addData(geojson);
            }
          },
          // @method addData( <GeoJSON> data ): this
          // Adds a GeoJSON object to the layer.
          addData: function(geojson) {
            var features = isArray(geojson) ? geojson : geojson.features, i, len, feature;
            if (features) {
              for (i = 0, len = features.length; i < len; i++) {
                feature = features[i];
                if (feature.geometries || feature.geometry || feature.features || feature.coordinates) {
                  this.addData(feature);
                }
              }
              return this;
            }
            var options = this.options;
            if (options.filter && !options.filter(geojson)) {
              return this;
            }
            var layer = geometryToLayer(geojson, options);
            if (!layer) {
              return this;
            }
            layer.feature = asFeature(geojson);
            layer.defaultOptions = layer.options;
            this.resetStyle(layer);
            if (options.onEachFeature) {
              options.onEachFeature(geojson, layer);
            }
            return this.addLayer(layer);
          },
          // @method resetStyle( <Path> layer? ): this
          // Resets the given vector layer's style to the original GeoJSON style, useful for resetting style after hover events.
          // If `layer` is omitted, the style of all features in the current layer is reset.
          resetStyle: function(layer) {
            if (layer === void 0) {
              return this.eachLayer(this.resetStyle, this);
            }
            layer.options = extend({}, layer.defaultOptions);
            this._setLayerStyle(layer, this.options.style);
            return this;
          },
          // @method setStyle( <Function> style ): this
          // Changes styles of GeoJSON vector layers with the given style function.
          setStyle: function(style2) {
            return this.eachLayer(function(layer) {
              this._setLayerStyle(layer, style2);
            }, this);
          },
          _setLayerStyle: function(layer, style2) {
            if (layer.setStyle) {
              if (typeof style2 === "function") {
                style2 = style2(layer.feature);
              }
              layer.setStyle(style2);
            }
          }
        });
        function geometryToLayer(geojson, options) {
          var geometry = geojson.type === "Feature" ? geojson.geometry : geojson, coords = geometry ? geometry.coordinates : null, layers2 = [], pointToLayer = options && options.pointToLayer, _coordsToLatLng = options && options.coordsToLatLng || coordsToLatLng, latlng, latlngs, i, len;
          if (!coords && !geometry) {
            return null;
          }
          switch (geometry.type) {
            case "Point":
              latlng = _coordsToLatLng(coords);
              return _pointToLayer(pointToLayer, geojson, latlng, options);
            case "MultiPoint":
              for (i = 0, len = coords.length; i < len; i++) {
                latlng = _coordsToLatLng(coords[i]);
                layers2.push(_pointToLayer(pointToLayer, geojson, latlng, options));
              }
              return new FeatureGroup(layers2);
            case "LineString":
            case "MultiLineString":
              latlngs = coordsToLatLngs(coords, geometry.type === "LineString" ? 0 : 1, _coordsToLatLng);
              return new Polyline(latlngs, options);
            case "Polygon":
            case "MultiPolygon":
              latlngs = coordsToLatLngs(coords, geometry.type === "Polygon" ? 1 : 2, _coordsToLatLng);
              return new Polygon(latlngs, options);
            case "GeometryCollection":
              for (i = 0, len = geometry.geometries.length; i < len; i++) {
                var geoLayer = geometryToLayer({
                  geometry: geometry.geometries[i],
                  type: "Feature",
                  properties: geojson.properties
                }, options);
                if (geoLayer) {
                  layers2.push(geoLayer);
                }
              }
              return new FeatureGroup(layers2);
            case "FeatureCollection":
              for (i = 0, len = geometry.features.length; i < len; i++) {
                var featureLayer = geometryToLayer(geometry.features[i], options);
                if (featureLayer) {
                  layers2.push(featureLayer);
                }
              }
              return new FeatureGroup(layers2);
            default:
              throw new Error("Invalid GeoJSON object.");
          }
        }
        function _pointToLayer(pointToLayerFn, geojson, latlng, options) {
          return pointToLayerFn ? pointToLayerFn(geojson, latlng) : new Marker(latlng, options && options.markersInheritOptions && options);
        }
        function coordsToLatLng(coords) {
          return new LatLng(coords[1], coords[0], coords[2]);
        }
        function coordsToLatLngs(coords, levelsDeep, _coordsToLatLng) {
          var latlngs = [];
          for (var i = 0, len = coords.length, latlng; i < len; i++) {
            latlng = levelsDeep ? coordsToLatLngs(coords[i], levelsDeep - 1, _coordsToLatLng) : (_coordsToLatLng || coordsToLatLng)(coords[i]);
            latlngs.push(latlng);
          }
          return latlngs;
        }
        function latLngToCoords(latlng, precision) {
          latlng = toLatLng(latlng);
          return latlng.alt !== void 0 ? [formatNum(latlng.lng, precision), formatNum(latlng.lat, precision), formatNum(latlng.alt, precision)] : [formatNum(latlng.lng, precision), formatNum(latlng.lat, precision)];
        }
        function latLngsToCoords(latlngs, levelsDeep, closed, precision) {
          var coords = [];
          for (var i = 0, len = latlngs.length; i < len; i++) {
            coords.push(levelsDeep ? latLngsToCoords(latlngs[i], isFlat(latlngs[i]) ? 0 : levelsDeep - 1, closed, precision) : latLngToCoords(latlngs[i], precision));
          }
          if (!levelsDeep && closed && coords.length > 0) {
            coords.push(coords[0].slice());
          }
          return coords;
        }
        function getFeature(layer, newGeometry) {
          return layer.feature ? extend({}, layer.feature, { geometry: newGeometry }) : asFeature(newGeometry);
        }
        function asFeature(geojson) {
          if (geojson.type === "Feature" || geojson.type === "FeatureCollection") {
            return geojson;
          }
          return {
            type: "Feature",
            properties: {},
            geometry: geojson
          };
        }
        var PointToGeoJSON = {
          toGeoJSON: function(precision) {
            return getFeature(this, {
              type: "Point",
              coordinates: latLngToCoords(this.getLatLng(), precision)
            });
          }
        };
        Marker.include(PointToGeoJSON);
        Circle.include(PointToGeoJSON);
        CircleMarker.include(PointToGeoJSON);
        Polyline.include({
          toGeoJSON: function(precision) {
            var multi = !isFlat(this._latlngs);
            var coords = latLngsToCoords(this._latlngs, multi ? 1 : 0, false, precision);
            return getFeature(this, {
              type: (multi ? "Multi" : "") + "LineString",
              coordinates: coords
            });
          }
        });
        Polygon.include({
          toGeoJSON: function(precision) {
            var holes = !isFlat(this._latlngs), multi = holes && !isFlat(this._latlngs[0]);
            var coords = latLngsToCoords(this._latlngs, multi ? 2 : holes ? 1 : 0, true, precision);
            if (!holes) {
              coords = [coords];
            }
            return getFeature(this, {
              type: (multi ? "Multi" : "") + "Polygon",
              coordinates: coords
            });
          }
        });
        LayerGroup.include({
          toMultiPoint: function(precision) {
            var coords = [];
            this.eachLayer(function(layer) {
              coords.push(layer.toGeoJSON(precision).geometry.coordinates);
            });
            return getFeature(this, {
              type: "MultiPoint",
              coordinates: coords
            });
          },
          // @method toGeoJSON(precision?: Number|false): Object
          // Coordinates values are rounded with [`formatNum`](#util-formatnum) function with given `precision`.
          // Returns a [`GeoJSON`](https://en.wikipedia.org/wiki/GeoJSON) representation of the layer group (as a GeoJSON `FeatureCollection`, `GeometryCollection`, or `MultiPoint`).
          toGeoJSON: function(precision) {
            var type = this.feature && this.feature.geometry && this.feature.geometry.type;
            if (type === "MultiPoint") {
              return this.toMultiPoint(precision);
            }
            var isGeometryCollection = type === "GeometryCollection", jsons = [];
            this.eachLayer(function(layer) {
              if (layer.toGeoJSON) {
                var json = layer.toGeoJSON(precision);
                if (isGeometryCollection) {
                  jsons.push(json.geometry);
                } else {
                  var feature = asFeature(json);
                  if (feature.type === "FeatureCollection") {
                    jsons.push.apply(jsons, feature.features);
                  } else {
                    jsons.push(feature);
                  }
                }
              }
            });
            if (isGeometryCollection) {
              return getFeature(this, {
                geometries: jsons,
                type: "GeometryCollection"
              });
            }
            return {
              type: "FeatureCollection",
              features: jsons
            };
          }
        });
        function geoJSON(geojson, options) {
          return new GeoJSON(geojson, options);
        }
        var geoJson = geoJSON;
        var ImageOverlay = Layer.extend({
          // @section
          // @aka ImageOverlay options
          options: {
            // @option opacity: Number = 1.0
            // The opacity of the image overlay.
            opacity: 1,
            // @option alt: String = ''
            // Text for the `alt` attribute of the image (useful for accessibility).
            alt: "",
            // @option interactive: Boolean = false
            // If `true`, the image overlay will emit [mouse events](#interactive-layer) when clicked or hovered.
            interactive: false,
            // @option crossOrigin: Boolean|String = false
            // Whether the crossOrigin attribute will be added to the image.
            // If a String is provided, the image will have its crossOrigin attribute set to the String provided. This is needed if you want to access image pixel data.
            // Refer to [CORS Settings](https://developer.mozilla.org/en-US/docs/Web/HTML/CORS_settings_attributes) for valid String values.
            crossOrigin: false,
            // @option errorOverlayUrl: String = ''
            // URL to the overlay image to show in place of the overlay that failed to load.
            errorOverlayUrl: "",
            // @option zIndex: Number = 1
            // The explicit [zIndex](https://developer.mozilla.org/docs/Web/CSS/CSS_Positioning/Understanding_z_index) of the overlay layer.
            zIndex: 1,
            // @option className: String = ''
            // A custom class name to assign to the image. Empty by default.
            className: ""
          },
          initialize: function(url, bounds, options) {
            this._url = url;
            this._bounds = toLatLngBounds(bounds);
            setOptions(this, options);
          },
          onAdd: function() {
            if (!this._image) {
              this._initImage();
              if (this.options.opacity < 1) {
                this._updateOpacity();
              }
            }
            if (this.options.interactive) {
              addClass(this._image, "leaflet-interactive");
              this.addInteractiveTarget(this._image);
            }
            this.getPane().appendChild(this._image);
            this._reset();
          },
          onRemove: function() {
            remove(this._image);
            if (this.options.interactive) {
              this.removeInteractiveTarget(this._image);
            }
          },
          // @method setOpacity(opacity: Number): this
          // Sets the opacity of the overlay.
          setOpacity: function(opacity) {
            this.options.opacity = opacity;
            if (this._image) {
              this._updateOpacity();
            }
            return this;
          },
          setStyle: function(styleOpts) {
            if (styleOpts.opacity) {
              this.setOpacity(styleOpts.opacity);
            }
            return this;
          },
          // @method bringToFront(): this
          // Brings the layer to the top of all overlays.
          bringToFront: function() {
            if (this._map) {
              toFront(this._image);
            }
            return this;
          },
          // @method bringToBack(): this
          // Brings the layer to the bottom of all overlays.
          bringToBack: function() {
            if (this._map) {
              toBack(this._image);
            }
            return this;
          },
          // @method setUrl(url: String): this
          // Changes the URL of the image.
          setUrl: function(url) {
            this._url = url;
            if (this._image) {
              this._image.src = url;
            }
            return this;
          },
          // @method setBounds(bounds: LatLngBounds): this
          // Update the bounds that this ImageOverlay covers
          setBounds: function(bounds) {
            this._bounds = toLatLngBounds(bounds);
            if (this._map) {
              this._reset();
            }
            return this;
          },
          getEvents: function() {
            var events = {
              zoom: this._reset,
              viewreset: this._reset
            };
            if (this._zoomAnimated) {
              events.zoomanim = this._animateZoom;
            }
            return events;
          },
          // @method setZIndex(value: Number): this
          // Changes the [zIndex](#imageoverlay-zindex) of the image overlay.
          setZIndex: function(value) {
            this.options.zIndex = value;
            this._updateZIndex();
            return this;
          },
          // @method getBounds(): LatLngBounds
          // Get the bounds that this ImageOverlay covers
          getBounds: function() {
            return this._bounds;
          },
          // @method getElement(): HTMLElement
          // Returns the instance of [`HTMLImageElement`](https://developer.mozilla.org/docs/Web/API/HTMLImageElement)
          // used by this overlay.
          getElement: function() {
            return this._image;
          },
          _initImage: function() {
            var wasElementSupplied = this._url.tagName === "IMG";
            var img = this._image = wasElementSupplied ? this._url : create$1("img");
            addClass(img, "leaflet-image-layer");
            if (this._zoomAnimated) {
              addClass(img, "leaflet-zoom-animated");
            }
            if (this.options.className) {
              addClass(img, this.options.className);
            }
            img.onselectstart = falseFn;
            img.onmousemove = falseFn;
            img.onload = bind(this.fire, this, "load");
            img.onerror = bind(this._overlayOnError, this, "error");
            if (this.options.crossOrigin || this.options.crossOrigin === "") {
              img.crossOrigin = this.options.crossOrigin === true ? "" : this.options.crossOrigin;
            }
            if (this.options.zIndex) {
              this._updateZIndex();
            }
            if (wasElementSupplied) {
              this._url = img.src;
              return;
            }
            img.src = this._url;
            img.alt = this.options.alt;
          },
          _animateZoom: function(e) {
            var scale2 = this._map.getZoomScale(e.zoom), offset = this._map._latLngBoundsToNewLayerBounds(this._bounds, e.zoom, e.center).min;
            setTransform(this._image, offset, scale2);
          },
          _reset: function() {
            var image = this._image, bounds = new Bounds(
              this._map.latLngToLayerPoint(this._bounds.getNorthWest()),
              this._map.latLngToLayerPoint(this._bounds.getSouthEast())
            ), size = bounds.getSize();
            setPosition(image, bounds.min);
            image.style.width = size.x + "px";
            image.style.height = size.y + "px";
          },
          _updateOpacity: function() {
            setOpacity(this._image, this.options.opacity);
          },
          _updateZIndex: function() {
            if (this._image && this.options.zIndex !== void 0 && this.options.zIndex !== null) {
              this._image.style.zIndex = this.options.zIndex;
            }
          },
          _overlayOnError: function() {
            this.fire("error");
            var errorUrl = this.options.errorOverlayUrl;
            if (errorUrl && this._url !== errorUrl) {
              this._url = errorUrl;
              this._image.src = errorUrl;
            }
          },
          // @method getCenter(): LatLng
          // Returns the center of the ImageOverlay.
          getCenter: function() {
            return this._bounds.getCenter();
          }
        });
        var imageOverlay = function(url, bounds, options) {
          return new ImageOverlay(url, bounds, options);
        };
        var VideoOverlay = ImageOverlay.extend({
          // @section
          // @aka VideoOverlay options
          options: {
            // @option autoplay: Boolean = true
            // Whether the video starts playing automatically when loaded.
            // On some browsers autoplay will only work with `muted: true`
            autoplay: true,
            // @option loop: Boolean = true
            // Whether the video will loop back to the beginning when played.
            loop: true,
            // @option keepAspectRatio: Boolean = true
            // Whether the video will save aspect ratio after the projection.
            // Relevant for supported browsers. See [browser compatibility](https://developer.mozilla.org/en-US/docs/Web/CSS/object-fit)
            keepAspectRatio: true,
            // @option muted: Boolean = false
            // Whether the video starts on mute when loaded.
            muted: false,
            // @option playsInline: Boolean = true
            // Mobile browsers will play the video right where it is instead of open it up in fullscreen mode.
            playsInline: true
          },
          _initImage: function() {
            var wasElementSupplied = this._url.tagName === "VIDEO";
            var vid = this._image = wasElementSupplied ? this._url : create$1("video");
            addClass(vid, "leaflet-image-layer");
            if (this._zoomAnimated) {
              addClass(vid, "leaflet-zoom-animated");
            }
            if (this.options.className) {
              addClass(vid, this.options.className);
            }
            vid.onselectstart = falseFn;
            vid.onmousemove = falseFn;
            vid.onloadeddata = bind(this.fire, this, "load");
            if (wasElementSupplied) {
              var sourceElements = vid.getElementsByTagName("source");
              var sources = [];
              for (var j = 0; j < sourceElements.length; j++) {
                sources.push(sourceElements[j].src);
              }
              this._url = sourceElements.length > 0 ? sources : [vid.src];
              return;
            }
            if (!isArray(this._url)) {
              this._url = [this._url];
            }
            if (!this.options.keepAspectRatio && Object.prototype.hasOwnProperty.call(vid.style, "objectFit")) {
              vid.style["objectFit"] = "fill";
            }
            vid.autoplay = !!this.options.autoplay;
            vid.loop = !!this.options.loop;
            vid.muted = !!this.options.muted;
            vid.playsInline = !!this.options.playsInline;
            for (var i = 0; i < this._url.length; i++) {
              var source = create$1("source");
              source.src = this._url[i];
              vid.appendChild(source);
            }
          }
          // @method getElement(): HTMLVideoElement
          // Returns the instance of [`HTMLVideoElement`](https://developer.mozilla.org/docs/Web/API/HTMLVideoElement)
          // used by this overlay.
        });
        function videoOverlay(video, bounds, options) {
          return new VideoOverlay(video, bounds, options);
        }
        var SVGOverlay = ImageOverlay.extend({
          _initImage: function() {
            var el = this._image = this._url;
            addClass(el, "leaflet-image-layer");
            if (this._zoomAnimated) {
              addClass(el, "leaflet-zoom-animated");
            }
            if (this.options.className) {
              addClass(el, this.options.className);
            }
            el.onselectstart = falseFn;
            el.onmousemove = falseFn;
          }
          // @method getElement(): SVGElement
          // Returns the instance of [`SVGElement`](https://developer.mozilla.org/docs/Web/API/SVGElement)
          // used by this overlay.
        });
        function svgOverlay(el, bounds, options) {
          return new SVGOverlay(el, bounds, options);
        }
        var DivOverlay = Layer.extend({
          // @section
          // @aka DivOverlay options
          options: {
            // @option interactive: Boolean = false
            // If true, the popup/tooltip will listen to the mouse events.
            interactive: false,
            // @option offset: Point = Point(0, 0)
            // The offset of the overlay position.
            offset: [0, 0],
            // @option className: String = ''
            // A custom CSS class name to assign to the overlay.
            className: "",
            // @option pane: String = undefined
            // `Map pane` where the overlay will be added.
            pane: void 0,
            // @option content: String|HTMLElement|Function = ''
            // Sets the HTML content of the overlay while initializing. If a function is passed the source layer will be
            // passed to the function. The function should return a `String` or `HTMLElement` to be used in the overlay.
            content: ""
          },
          initialize: function(options, source) {
            if (options && (options instanceof LatLng || isArray(options))) {
              this._latlng = toLatLng(options);
              setOptions(this, source);
            } else {
              setOptions(this, options);
              this._source = source;
            }
            if (this.options.content) {
              this._content = this.options.content;
            }
          },
          // @method openOn(map: Map): this
          // Adds the overlay to the map.
          // Alternative to `map.openPopup(popup)`/`.openTooltip(tooltip)`.
          openOn: function(map2) {
            map2 = arguments.length ? map2 : this._source._map;
            if (!map2.hasLayer(this)) {
              map2.addLayer(this);
            }
            return this;
          },
          // @method close(): this
          // Closes the overlay.
          // Alternative to `map.closePopup(popup)`/`.closeTooltip(tooltip)`
          // and `layer.closePopup()`/`.closeTooltip()`.
          close: function() {
            if (this._map) {
              this._map.removeLayer(this);
            }
            return this;
          },
          // @method toggle(layer?: Layer): this
          // Opens or closes the overlay bound to layer depending on its current state.
          // Argument may be omitted only for overlay bound to layer.
          // Alternative to `layer.togglePopup()`/`.toggleTooltip()`.
          toggle: function(layer) {
            if (this._map) {
              this.close();
            } else {
              if (arguments.length) {
                this._source = layer;
              } else {
                layer = this._source;
              }
              this._prepareOpen();
              this.openOn(layer._map);
            }
            return this;
          },
          onAdd: function(map2) {
            this._zoomAnimated = map2._zoomAnimated;
            if (!this._container) {
              this._initLayout();
            }
            if (map2._fadeAnimated) {
              setOpacity(this._container, 0);
            }
            clearTimeout(this._removeTimeout);
            this.getPane().appendChild(this._container);
            this.update();
            if (map2._fadeAnimated) {
              setOpacity(this._container, 1);
            }
            this.bringToFront();
            if (this.options.interactive) {
              addClass(this._container, "leaflet-interactive");
              this.addInteractiveTarget(this._container);
            }
          },
          onRemove: function(map2) {
            if (map2._fadeAnimated) {
              setOpacity(this._container, 0);
              this._removeTimeout = setTimeout(bind(remove, void 0, this._container), 200);
            } else {
              remove(this._container);
            }
            if (this.options.interactive) {
              removeClass(this._container, "leaflet-interactive");
              this.removeInteractiveTarget(this._container);
            }
          },
          // @namespace DivOverlay
          // @method getLatLng: LatLng
          // Returns the geographical point of the overlay.
          getLatLng: function() {
            return this._latlng;
          },
          // @method setLatLng(latlng: LatLng): this
          // Sets the geographical point where the overlay will open.
          setLatLng: function(latlng) {
            this._latlng = toLatLng(latlng);
            if (this._map) {
              this._updatePosition();
              this._adjustPan();
            }
            return this;
          },
          // @method getContent: String|HTMLElement
          // Returns the content of the overlay.
          getContent: function() {
            return this._content;
          },
          // @method setContent(htmlContent: String|HTMLElement|Function): this
          // Sets the HTML content of the overlay. If a function is passed the source layer will be passed to the function.
          // The function should return a `String` or `HTMLElement` to be used in the overlay.
          setContent: function(content) {
            this._content = content;
            this.update();
            return this;
          },
          // @method getElement: String|HTMLElement
          // Returns the HTML container of the overlay.
          getElement: function() {
            return this._container;
          },
          // @method update: null
          // Updates the overlay content, layout and position. Useful for updating the overlay after something inside changed, e.g. image loaded.
          update: function() {
            if (!this._map) {
              return;
            }
            this._container.style.visibility = "hidden";
            this._updateContent();
            this._updateLayout();
            this._updatePosition();
            this._container.style.visibility = "";
            this._adjustPan();
          },
          getEvents: function() {
            var events = {
              zoom: this._updatePosition,
              viewreset: this._updatePosition
            };
            if (this._zoomAnimated) {
              events.zoomanim = this._animateZoom;
            }
            return events;
          },
          // @method isOpen: Boolean
          // Returns `true` when the overlay is visible on the map.
          isOpen: function() {
            return !!this._map && this._map.hasLayer(this);
          },
          // @method bringToFront: this
          // Brings this overlay in front of other overlays (in the same map pane).
          bringToFront: function() {
            if (this._map) {
              toFront(this._container);
            }
            return this;
          },
          // @method bringToBack: this
          // Brings this overlay to the back of other overlays (in the same map pane).
          bringToBack: function() {
            if (this._map) {
              toBack(this._container);
            }
            return this;
          },
          // prepare bound overlay to open: update latlng pos / content source (for FeatureGroup)
          _prepareOpen: function(latlng) {
            var source = this._source;
            if (!source._map) {
              return false;
            }
            if (source instanceof FeatureGroup) {
              source = null;
              var layers2 = this._source._layers;
              for (var id in layers2) {
                if (layers2[id]._map) {
                  source = layers2[id];
                  break;
                }
              }
              if (!source) {
                return false;
              }
              this._source = source;
            }
            if (!latlng) {
              if (source.getCenter) {
                latlng = source.getCenter();
              } else if (source.getLatLng) {
                latlng = source.getLatLng();
              } else if (source.getBounds) {
                latlng = source.getBounds().getCenter();
              } else {
                throw new Error("Unable to get source layer LatLng.");
              }
            }
            this.setLatLng(latlng);
            if (this._map) {
              this.update();
            }
            return true;
          },
          _updateContent: function() {
            if (!this._content) {
              return;
            }
            var node = this._contentNode;
            var content = typeof this._content === "function" ? this._content(this._source || this) : this._content;
            if (typeof content === "string") {
              node.innerHTML = content;
            } else {
              while (node.hasChildNodes()) {
                node.removeChild(node.firstChild);
              }
              node.appendChild(content);
            }
            this.fire("contentupdate");
          },
          _updatePosition: function() {
            if (!this._map) {
              return;
            }
            var pos = this._map.latLngToLayerPoint(this._latlng), offset = toPoint(this.options.offset), anchor = this._getAnchor();
            if (this._zoomAnimated) {
              setPosition(this._container, pos.add(anchor));
            } else {
              offset = offset.add(pos).add(anchor);
            }
            var bottom = this._containerBottom = -offset.y, left = this._containerLeft = -Math.round(this._containerWidth / 2) + offset.x;
            this._container.style.bottom = bottom + "px";
            this._container.style.left = left + "px";
          },
          _getAnchor: function() {
            return [0, 0];
          }
        });
        Map2.include({
          _initOverlay: function(OverlayClass, content, latlng, options) {
            var overlay = content;
            if (!(overlay instanceof OverlayClass)) {
              overlay = new OverlayClass(options).setContent(content);
            }
            if (latlng) {
              overlay.setLatLng(latlng);
            }
            return overlay;
          }
        });
        Layer.include({
          _initOverlay: function(OverlayClass, old, content, options) {
            var overlay = content;
            if (overlay instanceof OverlayClass) {
              setOptions(overlay, options);
              overlay._source = this;
            } else {
              overlay = old && !options ? old : new OverlayClass(options, this);
              overlay.setContent(content);
            }
            return overlay;
          }
        });
        var Popup = DivOverlay.extend({
          // @section
          // @aka Popup options
          options: {
            // @option pane: String = 'popupPane'
            // `Map pane` where the popup will be added.
            pane: "popupPane",
            // @option offset: Point = Point(0, 7)
            // The offset of the popup position.
            offset: [0, 7],
            // @option maxWidth: Number = 300
            // Max width of the popup, in pixels.
            maxWidth: 300,
            // @option minWidth: Number = 50
            // Min width of the popup, in pixels.
            minWidth: 50,
            // @option maxHeight: Number = null
            // If set, creates a scrollable container of the given height
            // inside a popup if its content exceeds it.
            // The scrollable container can be styled using the
            // `leaflet-popup-scrolled` CSS class selector.
            maxHeight: null,
            // @option autoPan: Boolean = true
            // Set it to `false` if you don't want the map to do panning animation
            // to fit the opened popup.
            autoPan: true,
            // @option autoPanPaddingTopLeft: Point = null
            // The margin between the popup and the top left corner of the map
            // view after autopanning was performed.
            autoPanPaddingTopLeft: null,
            // @option autoPanPaddingBottomRight: Point = null
            // The margin between the popup and the bottom right corner of the map
            // view after autopanning was performed.
            autoPanPaddingBottomRight: null,
            // @option autoPanPadding: Point = Point(5, 5)
            // Equivalent of setting both top left and bottom right autopan padding to the same value.
            autoPanPadding: [5, 5],
            // @option keepInView: Boolean = false
            // Set it to `true` if you want to prevent users from panning the popup
            // off of the screen while it is open.
            keepInView: false,
            // @option closeButton: Boolean = true
            // Controls the presence of a close button in the popup.
            closeButton: true,
            // @option autoClose: Boolean = true
            // Set it to `false` if you want to override the default behavior of
            // the popup closing when another popup is opened.
            autoClose: true,
            // @option closeOnEscapeKey: Boolean = true
            // Set it to `false` if you want to override the default behavior of
            // the ESC key for closing of the popup.
            closeOnEscapeKey: true,
            // @option closeOnClick: Boolean = *
            // Set it if you want to override the default behavior of the popup closing when user clicks
            // on the map. Defaults to the map's [`closePopupOnClick`](#map-closepopuponclick) option.
            // @option className: String = ''
            // A custom CSS class name to assign to the popup.
            className: ""
          },
          // @namespace Popup
          // @method openOn(map: Map): this
          // Alternative to `map.openPopup(popup)`.
          // Adds the popup to the map and closes the previous one.
          openOn: function(map2) {
            map2 = arguments.length ? map2 : this._source._map;
            if (!map2.hasLayer(this) && map2._popup && map2._popup.options.autoClose) {
              map2.removeLayer(map2._popup);
            }
            map2._popup = this;
            return DivOverlay.prototype.openOn.call(this, map2);
          },
          onAdd: function(map2) {
            DivOverlay.prototype.onAdd.call(this, map2);
            map2.fire("popupopen", { popup: this });
            if (this._source) {
              this._source.fire("popupopen", { popup: this }, true);
              if (!(this._source instanceof Path)) {
                this._source.on("preclick", stopPropagation);
              }
            }
          },
          onRemove: function(map2) {
            DivOverlay.prototype.onRemove.call(this, map2);
            map2.fire("popupclose", { popup: this });
            if (this._source) {
              this._source.fire("popupclose", { popup: this }, true);
              if (!(this._source instanceof Path)) {
                this._source.off("preclick", stopPropagation);
              }
            }
          },
          getEvents: function() {
            var events = DivOverlay.prototype.getEvents.call(this);
            if (this.options.closeOnClick !== void 0 ? this.options.closeOnClick : this._map.options.closePopupOnClick) {
              events.preclick = this.close;
            }
            if (this.options.keepInView) {
              events.moveend = this._adjustPan;
            }
            return events;
          },
          _initLayout: function() {
            var prefix = "leaflet-popup", container = this._container = create$1(
              "div",
              prefix + " " + (this.options.className || "") + " leaflet-zoom-animated"
            );
            var wrapper = this._wrapper = create$1("div", prefix + "-content-wrapper", container);
            this._contentNode = create$1("div", prefix + "-content", wrapper);
            disableClickPropagation(container);
            disableScrollPropagation(this._contentNode);
            on(container, "contextmenu", stopPropagation);
            this._tipContainer = create$1("div", prefix + "-tip-container", container);
            this._tip = create$1("div", prefix + "-tip", this._tipContainer);
            if (this.options.closeButton) {
              var closeButton = this._closeButton = create$1("a", prefix + "-close-button", container);
              closeButton.setAttribute("role", "button");
              closeButton.setAttribute("aria-label", "Close popup");
              closeButton.href = "#close";
              closeButton.innerHTML = '<span aria-hidden="true">&#215;</span>';
              on(closeButton, "click", function(ev) {
                preventDefault(ev);
                this.close();
              }, this);
            }
          },
          _updateLayout: function() {
            var container = this._contentNode, style2 = container.style;
            style2.width = "";
            style2.whiteSpace = "nowrap";
            var width = container.offsetWidth;
            width = Math.min(width, this.options.maxWidth);
            width = Math.max(width, this.options.minWidth);
            style2.width = width + 1 + "px";
            style2.whiteSpace = "";
            style2.height = "";
            var height = container.offsetHeight, maxHeight = this.options.maxHeight, scrolledClass = "leaflet-popup-scrolled";
            if (maxHeight && height > maxHeight) {
              style2.height = maxHeight + "px";
              addClass(container, scrolledClass);
            } else {
              removeClass(container, scrolledClass);
            }
            this._containerWidth = this._container.offsetWidth;
          },
          _animateZoom: function(e) {
            var pos = this._map._latLngToNewLayerPoint(this._latlng, e.zoom, e.center), anchor = this._getAnchor();
            setPosition(this._container, pos.add(anchor));
          },
          _adjustPan: function() {
            if (!this.options.autoPan) {
              return;
            }
            if (this._map._panAnim) {
              this._map._panAnim.stop();
            }
            if (this._autopanning) {
              this._autopanning = false;
              return;
            }
            var map2 = this._map, marginBottom = parseInt(getStyle(this._container, "marginBottom"), 10) || 0, containerHeight = this._container.offsetHeight + marginBottom, containerWidth = this._containerWidth, layerPos = new Point(this._containerLeft, -containerHeight - this._containerBottom);
            layerPos._add(getPosition(this._container));
            var containerPos = map2.layerPointToContainerPoint(layerPos), padding = toPoint(this.options.autoPanPadding), paddingTL = toPoint(this.options.autoPanPaddingTopLeft || padding), paddingBR = toPoint(this.options.autoPanPaddingBottomRight || padding), size = map2.getSize(), dx = 0, dy = 0;
            if (containerPos.x + containerWidth + paddingBR.x > size.x) {
              dx = containerPos.x + containerWidth - size.x + paddingBR.x;
            }
            if (containerPos.x - dx - paddingTL.x < 0) {
              dx = containerPos.x - paddingTL.x;
            }
            if (containerPos.y + containerHeight + paddingBR.y > size.y) {
              dy = containerPos.y + containerHeight - size.y + paddingBR.y;
            }
            if (containerPos.y - dy - paddingTL.y < 0) {
              dy = containerPos.y - paddingTL.y;
            }
            if (dx || dy) {
              if (this.options.keepInView) {
                this._autopanning = true;
              }
              map2.fire("autopanstart").panBy([dx, dy]);
            }
          },
          _getAnchor: function() {
            return toPoint(this._source && this._source._getPopupAnchor ? this._source._getPopupAnchor() : [0, 0]);
          }
        });
        var popup = function(options, source) {
          return new Popup(options, source);
        };
        Map2.mergeOptions({
          closePopupOnClick: true
        });
        Map2.include({
          // @method openPopup(popup: Popup): this
          // Opens the specified popup while closing the previously opened (to make sure only one is opened at one time for usability).
          // @alternative
          // @method openPopup(content: String|HTMLElement, latlng: LatLng, options?: Popup options): this
          // Creates a popup with the specified content and options and opens it in the given point on a map.
          openPopup: function(popup2, latlng, options) {
            this._initOverlay(Popup, popup2, latlng, options).openOn(this);
            return this;
          },
          // @method closePopup(popup?: Popup): this
          // Closes the popup previously opened with [openPopup](#map-openpopup) (or the given one).
          closePopup: function(popup2) {
            popup2 = arguments.length ? popup2 : this._popup;
            if (popup2) {
              popup2.close();
            }
            return this;
          }
        });
        Layer.include({
          // @method bindPopup(content: String|HTMLElement|Function|Popup, options?: Popup options): this
          // Binds a popup to the layer with the passed `content` and sets up the
          // necessary event listeners. If a `Function` is passed it will receive
          // the layer as the first argument and should return a `String` or `HTMLElement`.
          bindPopup: function(content, options) {
            this._popup = this._initOverlay(Popup, this._popup, content, options);
            if (!this._popupHandlersAdded) {
              this.on({
                click: this._openPopup,
                keypress: this._onKeyPress,
                remove: this.closePopup,
                move: this._movePopup
              });
              this._popupHandlersAdded = true;
            }
            return this;
          },
          // @method unbindPopup(): this
          // Removes the popup previously bound with `bindPopup`.
          unbindPopup: function() {
            if (this._popup) {
              this.off({
                click: this._openPopup,
                keypress: this._onKeyPress,
                remove: this.closePopup,
                move: this._movePopup
              });
              this._popupHandlersAdded = false;
              this._popup = null;
            }
            return this;
          },
          // @method openPopup(latlng?: LatLng): this
          // Opens the bound popup at the specified `latlng` or at the default popup anchor if no `latlng` is passed.
          openPopup: function(latlng) {
            if (this._popup) {
              if (!(this instanceof FeatureGroup)) {
                this._popup._source = this;
              }
              if (this._popup._prepareOpen(latlng || this._latlng)) {
                this._popup.openOn(this._map);
              }
            }
            return this;
          },
          // @method closePopup(): this
          // Closes the popup bound to this layer if it is open.
          closePopup: function() {
            if (this._popup) {
              this._popup.close();
            }
            return this;
          },
          // @method togglePopup(): this
          // Opens or closes the popup bound to this layer depending on its current state.
          togglePopup: function() {
            if (this._popup) {
              this._popup.toggle(this);
            }
            return this;
          },
          // @method isPopupOpen(): boolean
          // Returns `true` if the popup bound to this layer is currently open.
          isPopupOpen: function() {
            return this._popup ? this._popup.isOpen() : false;
          },
          // @method setPopupContent(content: String|HTMLElement|Popup): this
          // Sets the content of the popup bound to this layer.
          setPopupContent: function(content) {
            if (this._popup) {
              this._popup.setContent(content);
            }
            return this;
          },
          // @method getPopup(): Popup
          // Returns the popup bound to this layer.
          getPopup: function() {
            return this._popup;
          },
          _openPopup: function(e) {
            if (!this._popup || !this._map) {
              return;
            }
            stop(e);
            var target = e.layer || e.target;
            if (this._popup._source === target && !(target instanceof Path)) {
              if (this._map.hasLayer(this._popup)) {
                this.closePopup();
              } else {
                this.openPopup(e.latlng);
              }
              return;
            }
            this._popup._source = target;
            this.openPopup(e.latlng);
          },
          _movePopup: function(e) {
            this._popup.setLatLng(e.latlng);
          },
          _onKeyPress: function(e) {
            if (e.originalEvent.keyCode === 13) {
              this._openPopup(e);
            }
          }
        });
        var Tooltip = DivOverlay.extend({
          // @section
          // @aka Tooltip options
          options: {
            // @option pane: String = 'tooltipPane'
            // `Map pane` where the tooltip will be added.
            pane: "tooltipPane",
            // @option offset: Point = Point(0, 0)
            // Optional offset of the tooltip position.
            offset: [0, 0],
            // @option direction: String = 'auto'
            // Direction where to open the tooltip. Possible values are: `right`, `left`,
            // `top`, `bottom`, `center`, `auto`.
            // `auto` will dynamically switch between `right` and `left` according to the tooltip
            // position on the map.
            direction: "auto",
            // @option permanent: Boolean = false
            // Whether to open the tooltip permanently or only on mouseover.
            permanent: false,
            // @option sticky: Boolean = false
            // If true, the tooltip will follow the mouse instead of being fixed at the feature center.
            sticky: false,
            // @option opacity: Number = 0.9
            // Tooltip container opacity.
            opacity: 0.9
          },
          onAdd: function(map2) {
            DivOverlay.prototype.onAdd.call(this, map2);
            this.setOpacity(this.options.opacity);
            map2.fire("tooltipopen", { tooltip: this });
            if (this._source) {
              this.addEventParent(this._source);
              this._source.fire("tooltipopen", { tooltip: this }, true);
            }
          },
          onRemove: function(map2) {
            DivOverlay.prototype.onRemove.call(this, map2);
            map2.fire("tooltipclose", { tooltip: this });
            if (this._source) {
              this.removeEventParent(this._source);
              this._source.fire("tooltipclose", { tooltip: this }, true);
            }
          },
          getEvents: function() {
            var events = DivOverlay.prototype.getEvents.call(this);
            if (!this.options.permanent) {
              events.preclick = this.close;
            }
            return events;
          },
          _initLayout: function() {
            var prefix = "leaflet-tooltip", className = prefix + " " + (this.options.className || "") + " leaflet-zoom-" + (this._zoomAnimated ? "animated" : "hide");
            this._contentNode = this._container = create$1("div", className);
            this._container.setAttribute("role", "tooltip");
            this._container.setAttribute("id", "leaflet-tooltip-" + stamp(this));
          },
          _updateLayout: function() {
          },
          _adjustPan: function() {
          },
          _setPosition: function(pos) {
            var subX, subY, map2 = this._map, container = this._container, centerPoint = map2.latLngToContainerPoint(map2.getCenter()), tooltipPoint = map2.layerPointToContainerPoint(pos), direction = this.options.direction, tooltipWidth = container.offsetWidth, tooltipHeight = container.offsetHeight, offset = toPoint(this.options.offset), anchor = this._getAnchor();
            if (direction === "top") {
              subX = tooltipWidth / 2;
              subY = tooltipHeight;
            } else if (direction === "bottom") {
              subX = tooltipWidth / 2;
              subY = 0;
            } else if (direction === "center") {
              subX = tooltipWidth / 2;
              subY = tooltipHeight / 2;
            } else if (direction === "right") {
              subX = 0;
              subY = tooltipHeight / 2;
            } else if (direction === "left") {
              subX = tooltipWidth;
              subY = tooltipHeight / 2;
            } else if (tooltipPoint.x < centerPoint.x) {
              direction = "right";
              subX = 0;
              subY = tooltipHeight / 2;
            } else {
              direction = "left";
              subX = tooltipWidth + (offset.x + anchor.x) * 2;
              subY = tooltipHeight / 2;
            }
            pos = pos.subtract(toPoint(subX, subY, true)).add(offset).add(anchor);
            removeClass(container, "leaflet-tooltip-right");
            removeClass(container, "leaflet-tooltip-left");
            removeClass(container, "leaflet-tooltip-top");
            removeClass(container, "leaflet-tooltip-bottom");
            addClass(container, "leaflet-tooltip-" + direction);
            setPosition(container, pos);
          },
          _updatePosition: function() {
            var pos = this._map.latLngToLayerPoint(this._latlng);
            this._setPosition(pos);
          },
          setOpacity: function(opacity) {
            this.options.opacity = opacity;
            if (this._container) {
              setOpacity(this._container, opacity);
            }
          },
          _animateZoom: function(e) {
            var pos = this._map._latLngToNewLayerPoint(this._latlng, e.zoom, e.center);
            this._setPosition(pos);
          },
          _getAnchor: function() {
            return toPoint(this._source && this._source._getTooltipAnchor && !this.options.sticky ? this._source._getTooltipAnchor() : [0, 0]);
          }
        });
        var tooltip = function(options, source) {
          return new Tooltip(options, source);
        };
        Map2.include({
          // @method openTooltip(tooltip: Tooltip): this
          // Opens the specified tooltip.
          // @alternative
          // @method openTooltip(content: String|HTMLElement, latlng: LatLng, options?: Tooltip options): this
          // Creates a tooltip with the specified content and options and open it.
          openTooltip: function(tooltip2, latlng, options) {
            this._initOverlay(Tooltip, tooltip2, latlng, options).openOn(this);
            return this;
          },
          // @method closeTooltip(tooltip: Tooltip): this
          // Closes the tooltip given as parameter.
          closeTooltip: function(tooltip2) {
            tooltip2.close();
            return this;
          }
        });
        Layer.include({
          // @method bindTooltip(content: String|HTMLElement|Function|Tooltip, options?: Tooltip options): this
          // Binds a tooltip to the layer with the passed `content` and sets up the
          // necessary event listeners. If a `Function` is passed it will receive
          // the layer as the first argument and should return a `String` or `HTMLElement`.
          bindTooltip: function(content, options) {
            if (this._tooltip && this.isTooltipOpen()) {
              this.unbindTooltip();
            }
            this._tooltip = this._initOverlay(Tooltip, this._tooltip, content, options);
            this._initTooltipInteractions();
            if (this._tooltip.options.permanent && this._map && this._map.hasLayer(this)) {
              this.openTooltip();
            }
            return this;
          },
          // @method unbindTooltip(): this
          // Removes the tooltip previously bound with `bindTooltip`.
          unbindTooltip: function() {
            if (this._tooltip) {
              this._initTooltipInteractions(true);
              this.closeTooltip();
              this._tooltip = null;
            }
            return this;
          },
          _initTooltipInteractions: function(remove2) {
            if (!remove2 && this._tooltipHandlersAdded) {
              return;
            }
            var onOff = remove2 ? "off" : "on", events = {
              remove: this.closeTooltip,
              move: this._moveTooltip
            };
            if (!this._tooltip.options.permanent) {
              events.mouseover = this._openTooltip;
              events.mouseout = this.closeTooltip;
              events.click = this._openTooltip;
              if (this._map) {
                this._addFocusListeners();
              } else {
                events.add = this._addFocusListeners;
              }
            } else {
              events.add = this._openTooltip;
            }
            if (this._tooltip.options.sticky) {
              events.mousemove = this._moveTooltip;
            }
            this[onOff](events);
            this._tooltipHandlersAdded = !remove2;
          },
          // @method openTooltip(latlng?: LatLng): this
          // Opens the bound tooltip at the specified `latlng` or at the default tooltip anchor if no `latlng` is passed.
          openTooltip: function(latlng) {
            if (this._tooltip) {
              if (!(this instanceof FeatureGroup)) {
                this._tooltip._source = this;
              }
              if (this._tooltip._prepareOpen(latlng)) {
                this._tooltip.openOn(this._map);
                if (this.getElement) {
                  this._setAriaDescribedByOnLayer(this);
                } else if (this.eachLayer) {
                  this.eachLayer(this._setAriaDescribedByOnLayer, this);
                }
              }
            }
            return this;
          },
          // @method closeTooltip(): this
          // Closes the tooltip bound to this layer if it is open.
          closeTooltip: function() {
            if (this._tooltip) {
              return this._tooltip.close();
            }
          },
          // @method toggleTooltip(): this
          // Opens or closes the tooltip bound to this layer depending on its current state.
          toggleTooltip: function() {
            if (this._tooltip) {
              this._tooltip.toggle(this);
            }
            return this;
          },
          // @method isTooltipOpen(): boolean
          // Returns `true` if the tooltip bound to this layer is currently open.
          isTooltipOpen: function() {
            return this._tooltip.isOpen();
          },
          // @method setTooltipContent(content: String|HTMLElement|Tooltip): this
          // Sets the content of the tooltip bound to this layer.
          setTooltipContent: function(content) {
            if (this._tooltip) {
              this._tooltip.setContent(content);
            }
            return this;
          },
          // @method getTooltip(): Tooltip
          // Returns the tooltip bound to this layer.
          getTooltip: function() {
            return this._tooltip;
          },
          _addFocusListeners: function() {
            if (this.getElement) {
              this._addFocusListenersOnLayer(this);
            } else if (this.eachLayer) {
              this.eachLayer(this._addFocusListenersOnLayer, this);
            }
          },
          _addFocusListenersOnLayer: function(layer) {
            var el = typeof layer.getElement === "function" && layer.getElement();
            if (el) {
              on(el, "focus", function() {
                this._tooltip._source = layer;
                this.openTooltip();
              }, this);
              on(el, "blur", this.closeTooltip, this);
            }
          },
          _setAriaDescribedByOnLayer: function(layer) {
            var el = typeof layer.getElement === "function" && layer.getElement();
            if (el) {
              el.setAttribute("aria-describedby", this._tooltip._container.id);
            }
          },
          _openTooltip: function(e) {
            if (!this._tooltip || !this._map) {
              return;
            }
            if (this._map.dragging && this._map.dragging.moving() && !this._openOnceFlag) {
              this._openOnceFlag = true;
              var that = this;
              this._map.once("moveend", function() {
                that._openOnceFlag = false;
                that._openTooltip(e);
              });
              return;
            }
            this._tooltip._source = e.layer || e.target;
            this.openTooltip(this._tooltip.options.sticky ? e.latlng : void 0);
          },
          _moveTooltip: function(e) {
            var latlng = e.latlng, containerPoint, layerPoint;
            if (this._tooltip.options.sticky && e.originalEvent) {
              containerPoint = this._map.mouseEventToContainerPoint(e.originalEvent);
              layerPoint = this._map.containerPointToLayerPoint(containerPoint);
              latlng = this._map.layerPointToLatLng(layerPoint);
            }
            this._tooltip.setLatLng(latlng);
          }
        });
        var DivIcon = Icon.extend({
          options: {
            // @section
            // @aka DivIcon options
            iconSize: [12, 12],
            // also can be set through CSS
            // iconAnchor: (Point),
            // popupAnchor: (Point),
            // @option html: String|HTMLElement = ''
            // Custom HTML code to put inside the div element, empty by default. Alternatively,
            // an instance of `HTMLElement`.
            html: false,
            // @option bgPos: Point = [0, 0]
            // Optional relative position of the background, in pixels
            bgPos: null,
            className: "leaflet-div-icon"
          },
          createIcon: function(oldIcon) {
            var div = oldIcon && oldIcon.tagName === "DIV" ? oldIcon : document.createElement("div"), options = this.options;
            if (options.html instanceof Element) {
              empty(div);
              div.appendChild(options.html);
            } else {
              div.innerHTML = options.html !== false ? options.html : "";
            }
            if (options.bgPos) {
              var bgPos = toPoint(options.bgPos);
              div.style.backgroundPosition = -bgPos.x + "px " + -bgPos.y + "px";
            }
            this._setIconStyles(div, "icon");
            return div;
          },
          createShadow: function() {
            return null;
          }
        });
        function divIcon(options) {
          return new DivIcon(options);
        }
        Icon.Default = IconDefault;
        var GridLayer = Layer.extend({
          // @section
          // @aka GridLayer options
          options: {
            // @option tileSize: Number|Point = 256
            // Width and height of tiles in the grid. Use a number if width and height are equal, or `L.point(width, height)` otherwise.
            tileSize: 256,
            // @option opacity: Number = 1.0
            // Opacity of the tiles. Can be used in the `createTile()` function.
            opacity: 1,
            // @option updateWhenIdle: Boolean = (depends)
            // Load new tiles only when panning ends.
            // `true` by default on mobile browsers, in order to avoid too many requests and keep smooth navigation.
            // `false` otherwise in order to display new tiles _during_ panning, since it is easy to pan outside the
            // [`keepBuffer`](#gridlayer-keepbuffer) option in desktop browsers.
            updateWhenIdle: Browser.mobile,
            // @option updateWhenZooming: Boolean = true
            // By default, a smooth zoom animation (during a [touch zoom](#map-touchzoom) or a [`flyTo()`](#map-flyto)) will update grid layers every integer zoom level. Setting this option to `false` will update the grid layer only when the smooth animation ends.
            updateWhenZooming: true,
            // @option updateInterval: Number = 200
            // Tiles will not update more than once every `updateInterval` milliseconds when panning.
            updateInterval: 200,
            // @option zIndex: Number = 1
            // The explicit zIndex of the tile layer.
            zIndex: 1,
            // @option bounds: LatLngBounds = undefined
            // If set, tiles will only be loaded inside the set `LatLngBounds`.
            bounds: null,
            // @option minZoom: Number = 0
            // The minimum zoom level down to which this layer will be displayed (inclusive).
            minZoom: 0,
            // @option maxZoom: Number = undefined
            // The maximum zoom level up to which this layer will be displayed (inclusive).
            maxZoom: void 0,
            // @option maxNativeZoom: Number = undefined
            // Maximum zoom number the tile source has available. If it is specified,
            // the tiles on all zoom levels higher than `maxNativeZoom` will be loaded
            // from `maxNativeZoom` level and auto-scaled.
            maxNativeZoom: void 0,
            // @option minNativeZoom: Number = undefined
            // Minimum zoom number the tile source has available. If it is specified,
            // the tiles on all zoom levels lower than `minNativeZoom` will be loaded
            // from `minNativeZoom` level and auto-scaled.
            minNativeZoom: void 0,
            // @option noWrap: Boolean = false
            // Whether the layer is wrapped around the antimeridian. If `true`, the
            // GridLayer will only be displayed once at low zoom levels. Has no
            // effect when the [map CRS](#map-crs) doesn't wrap around. Can be used
            // in combination with [`bounds`](#gridlayer-bounds) to prevent requesting
            // tiles outside the CRS limits.
            noWrap: false,
            // @option pane: String = 'tilePane'
            // `Map pane` where the grid layer will be added.
            pane: "tilePane",
            // @option className: String = ''
            // A custom class name to assign to the tile layer. Empty by default.
            className: "",
            // @option keepBuffer: Number = 2
            // When panning the map, keep this many rows and columns of tiles before unloading them.
            keepBuffer: 2
          },
          initialize: function(options) {
            setOptions(this, options);
          },
          onAdd: function() {
            this._initContainer();
            this._levels = {};
            this._tiles = {};
            this._resetView();
          },
          beforeAdd: function(map2) {
            map2._addZoomLimit(this);
          },
          onRemove: function(map2) {
            this._removeAllTiles();
            remove(this._container);
            map2._removeZoomLimit(this);
            this._container = null;
            this._tileZoom = void 0;
          },
          // @method bringToFront: this
          // Brings the tile layer to the top of all tile layers.
          bringToFront: function() {
            if (this._map) {
              toFront(this._container);
              this._setAutoZIndex(Math.max);
            }
            return this;
          },
          // @method bringToBack: this
          // Brings the tile layer to the bottom of all tile layers.
          bringToBack: function() {
            if (this._map) {
              toBack(this._container);
              this._setAutoZIndex(Math.min);
            }
            return this;
          },
          // @method getContainer: HTMLElement
          // Returns the HTML element that contains the tiles for this layer.
          getContainer: function() {
            return this._container;
          },
          // @method setOpacity(opacity: Number): this
          // Changes the [opacity](#gridlayer-opacity) of the grid layer.
          setOpacity: function(opacity) {
            this.options.opacity = opacity;
            this._updateOpacity();
            return this;
          },
          // @method setZIndex(zIndex: Number): this
          // Changes the [zIndex](#gridlayer-zindex) of the grid layer.
          setZIndex: function(zIndex) {
            this.options.zIndex = zIndex;
            this._updateZIndex();
            return this;
          },
          // @method isLoading: Boolean
          // Returns `true` if any tile in the grid layer has not finished loading.
          isLoading: function() {
            return this._loading;
          },
          // @method redraw: this
          // Causes the layer to clear all the tiles and request them again.
          redraw: function() {
            if (this._map) {
              this._removeAllTiles();
              var tileZoom = this._clampZoom(this._map.getZoom());
              if (tileZoom !== this._tileZoom) {
                this._tileZoom = tileZoom;
                this._updateLevels();
              }
              this._update();
            }
            return this;
          },
          getEvents: function() {
            var events = {
              viewprereset: this._invalidateAll,
              viewreset: this._resetView,
              zoom: this._resetView,
              moveend: this._onMoveEnd
            };
            if (!this.options.updateWhenIdle) {
              if (!this._onMove) {
                this._onMove = throttle(this._onMoveEnd, this.options.updateInterval, this);
              }
              events.move = this._onMove;
            }
            if (this._zoomAnimated) {
              events.zoomanim = this._animateZoom;
            }
            return events;
          },
          // @section Extension methods
          // Layers extending `GridLayer` shall reimplement the following method.
          // @method createTile(coords: Object, done?: Function): HTMLElement
          // Called only internally, must be overridden by classes extending `GridLayer`.
          // Returns the `HTMLElement` corresponding to the given `coords`. If the `done` callback
          // is specified, it must be called when the tile has finished loading and drawing.
          createTile: function() {
            return document.createElement("div");
          },
          // @section
          // @method getTileSize: Point
          // Normalizes the [tileSize option](#gridlayer-tilesize) into a point. Used by the `createTile()` method.
          getTileSize: function() {
            var s = this.options.tileSize;
            return s instanceof Point ? s : new Point(s, s);
          },
          _updateZIndex: function() {
            if (this._container && this.options.zIndex !== void 0 && this.options.zIndex !== null) {
              this._container.style.zIndex = this.options.zIndex;
            }
          },
          _setAutoZIndex: function(compare) {
            var layers2 = this.getPane().children, edgeZIndex = -compare(-Infinity, Infinity);
            for (var i = 0, len = layers2.length, zIndex; i < len; i++) {
              zIndex = layers2[i].style.zIndex;
              if (layers2[i] !== this._container && zIndex) {
                edgeZIndex = compare(edgeZIndex, +zIndex);
              }
            }
            if (isFinite(edgeZIndex)) {
              this.options.zIndex = edgeZIndex + compare(-1, 1);
              this._updateZIndex();
            }
          },
          _updateOpacity: function() {
            if (!this._map) {
              return;
            }
            if (Browser.ielt9) {
              return;
            }
            setOpacity(this._container, this.options.opacity);
            var now = +/* @__PURE__ */ new Date(), nextFrame = false, willPrune = false;
            for (var key in this._tiles) {
              var tile = this._tiles[key];
              if (!tile.current || !tile.loaded) {
                continue;
              }
              var fade = Math.min(1, (now - tile.loaded) / 200);
              setOpacity(tile.el, fade);
              if (fade < 1) {
                nextFrame = true;
              } else {
                if (tile.active) {
                  willPrune = true;
                } else {
                  this._onOpaqueTile(tile);
                }
                tile.active = true;
              }
            }
            if (willPrune && !this._noPrune) {
              this._pruneTiles();
            }
            if (nextFrame) {
              cancelAnimFrame(this._fadeFrame);
              this._fadeFrame = requestAnimFrame(this._updateOpacity, this);
            }
          },
          _onOpaqueTile: falseFn,
          _initContainer: function() {
            if (this._container) {
              return;
            }
            this._container = create$1("div", "leaflet-layer " + (this.options.className || ""));
            this._updateZIndex();
            if (this.options.opacity < 1) {
              this._updateOpacity();
            }
            this.getPane().appendChild(this._container);
          },
          _updateLevels: function() {
            var zoom2 = this._tileZoom, maxZoom = this.options.maxZoom;
            if (zoom2 === void 0) {
              return void 0;
            }
            for (var z in this._levels) {
              z = Number(z);
              if (this._levels[z].el.children.length || z === zoom2) {
                this._levels[z].el.style.zIndex = maxZoom - Math.abs(zoom2 - z);
                this._onUpdateLevel(z);
              } else {
                remove(this._levels[z].el);
                this._removeTilesAtZoom(z);
                this._onRemoveLevel(z);
                delete this._levels[z];
              }
            }
            var level = this._levels[zoom2], map2 = this._map;
            if (!level) {
              level = this._levels[zoom2] = {};
              level.el = create$1("div", "leaflet-tile-container leaflet-zoom-animated", this._container);
              level.el.style.zIndex = maxZoom;
              level.origin = map2.project(map2.unproject(map2.getPixelOrigin()), zoom2).round();
              level.zoom = zoom2;
              this._setZoomTransform(level, map2.getCenter(), map2.getZoom());
              falseFn(level.el.offsetWidth);
              this._onCreateLevel(level);
            }
            this._level = level;
            return level;
          },
          _onUpdateLevel: falseFn,
          _onRemoveLevel: falseFn,
          _onCreateLevel: falseFn,
          _pruneTiles: function() {
            if (!this._map) {
              return;
            }
            var key, tile;
            var zoom2 = this._map.getZoom();
            if (zoom2 > this.options.maxZoom || zoom2 < this.options.minZoom) {
              this._removeAllTiles();
              return;
            }
            for (key in this._tiles) {
              tile = this._tiles[key];
              tile.retain = tile.current;
            }
            for (key in this._tiles) {
              tile = this._tiles[key];
              if (tile.current && !tile.active) {
                var coords = tile.coords;
                if (!this._retainParent(coords.x, coords.y, coords.z, coords.z - 5)) {
                  this._retainChildren(coords.x, coords.y, coords.z, coords.z + 2);
                }
              }
            }
            for (key in this._tiles) {
              if (!this._tiles[key].retain) {
                this._removeTile(key);
              }
            }
          },
          _removeTilesAtZoom: function(zoom2) {
            for (var key in this._tiles) {
              if (this._tiles[key].coords.z !== zoom2) {
                continue;
              }
              this._removeTile(key);
            }
          },
          _removeAllTiles: function() {
            for (var key in this._tiles) {
              this._removeTile(key);
            }
          },
          _invalidateAll: function() {
            for (var z in this._levels) {
              remove(this._levels[z].el);
              this._onRemoveLevel(Number(z));
              delete this._levels[z];
            }
            this._removeAllTiles();
            this._tileZoom = void 0;
          },
          _retainParent: function(x, y, z, minZoom) {
            var x2 = Math.floor(x / 2), y2 = Math.floor(y / 2), z2 = z - 1, coords2 = new Point(+x2, +y2);
            coords2.z = +z2;
            var key = this._tileCoordsToKey(coords2), tile = this._tiles[key];
            if (tile && tile.active) {
              tile.retain = true;
              return true;
            } else if (tile && tile.loaded) {
              tile.retain = true;
            }
            if (z2 > minZoom) {
              return this._retainParent(x2, y2, z2, minZoom);
            }
            return false;
          },
          _retainChildren: function(x, y, z, maxZoom) {
            for (var i = 2 * x; i < 2 * x + 2; i++) {
              for (var j = 2 * y; j < 2 * y + 2; j++) {
                var coords = new Point(i, j);
                coords.z = z + 1;
                var key = this._tileCoordsToKey(coords), tile = this._tiles[key];
                if (tile && tile.active) {
                  tile.retain = true;
                  continue;
                } else if (tile && tile.loaded) {
                  tile.retain = true;
                }
                if (z + 1 < maxZoom) {
                  this._retainChildren(i, j, z + 1, maxZoom);
                }
              }
            }
          },
          _resetView: function(e) {
            var animating = e && (e.pinch || e.flyTo);
            this._setView(this._map.getCenter(), this._map.getZoom(), animating, animating);
          },
          _animateZoom: function(e) {
            this._setView(e.center, e.zoom, true, e.noUpdate);
          },
          _clampZoom: function(zoom2) {
            var options = this.options;
            if (void 0 !== options.minNativeZoom && zoom2 < options.minNativeZoom) {
              return options.minNativeZoom;
            }
            if (void 0 !== options.maxNativeZoom && options.maxNativeZoom < zoom2) {
              return options.maxNativeZoom;
            }
            return zoom2;
          },
          _setView: function(center, zoom2, noPrune, noUpdate) {
            var tileZoom = Math.round(zoom2);
            if (this.options.maxZoom !== void 0 && tileZoom > this.options.maxZoom || this.options.minZoom !== void 0 && tileZoom < this.options.minZoom) {
              tileZoom = void 0;
            } else {
              tileZoom = this._clampZoom(tileZoom);
            }
            var tileZoomChanged = this.options.updateWhenZooming && tileZoom !== this._tileZoom;
            if (!noUpdate || tileZoomChanged) {
              this._tileZoom = tileZoom;
              if (this._abortLoading) {
                this._abortLoading();
              }
              this._updateLevels();
              this._resetGrid();
              if (tileZoom !== void 0) {
                this._update(center);
              }
              if (!noPrune) {
                this._pruneTiles();
              }
              this._noPrune = !!noPrune;
            }
            this._setZoomTransforms(center, zoom2);
          },
          _setZoomTransforms: function(center, zoom2) {
            for (var i in this._levels) {
              this._setZoomTransform(this._levels[i], center, zoom2);
            }
          },
          _setZoomTransform: function(level, center, zoom2) {
            var scale2 = this._map.getZoomScale(zoom2, level.zoom), translate = level.origin.multiplyBy(scale2).subtract(this._map._getNewPixelOrigin(center, zoom2)).round();
            if (Browser.any3d) {
              setTransform(level.el, translate, scale2);
            } else {
              setPosition(level.el, translate);
            }
          },
          _resetGrid: function() {
            var map2 = this._map, crs = map2.options.crs, tileSize = this._tileSize = this.getTileSize(), tileZoom = this._tileZoom;
            var bounds = this._map.getPixelWorldBounds(this._tileZoom);
            if (bounds) {
              this._globalTileRange = this._pxBoundsToTileRange(bounds);
            }
            this._wrapX = crs.wrapLng && !this.options.noWrap && [
              Math.floor(map2.project([0, crs.wrapLng[0]], tileZoom).x / tileSize.x),
              Math.ceil(map2.project([0, crs.wrapLng[1]], tileZoom).x / tileSize.y)
            ];
            this._wrapY = crs.wrapLat && !this.options.noWrap && [
              Math.floor(map2.project([crs.wrapLat[0], 0], tileZoom).y / tileSize.x),
              Math.ceil(map2.project([crs.wrapLat[1], 0], tileZoom).y / tileSize.y)
            ];
          },
          _onMoveEnd: function() {
            if (!this._map || this._map._animatingZoom) {
              return;
            }
            this._update();
          },
          _getTiledPixelBounds: function(center) {
            var map2 = this._map, mapZoom = map2._animatingZoom ? Math.max(map2._animateToZoom, map2.getZoom()) : map2.getZoom(), scale2 = map2.getZoomScale(mapZoom, this._tileZoom), pixelCenter = map2.project(center, this._tileZoom).floor(), halfSize = map2.getSize().divideBy(scale2 * 2);
            return new Bounds(pixelCenter.subtract(halfSize), pixelCenter.add(halfSize));
          },
          // Private method to load tiles in the grid's active zoom level according to map bounds
          _update: function(center) {
            var map2 = this._map;
            if (!map2) {
              return;
            }
            var zoom2 = this._clampZoom(map2.getZoom());
            if (center === void 0) {
              center = map2.getCenter();
            }
            if (this._tileZoom === void 0) {
              return;
            }
            var pixelBounds = this._getTiledPixelBounds(center), tileRange = this._pxBoundsToTileRange(pixelBounds), tileCenter = tileRange.getCenter(), queue = [], margin = this.options.keepBuffer, noPruneRange = new Bounds(
              tileRange.getBottomLeft().subtract([margin, -margin]),
              tileRange.getTopRight().add([margin, -margin])
            );
            if (!(isFinite(tileRange.min.x) && isFinite(tileRange.min.y) && isFinite(tileRange.max.x) && isFinite(tileRange.max.y))) {
              throw new Error("Attempted to load an infinite number of tiles");
            }
            for (var key in this._tiles) {
              var c = this._tiles[key].coords;
              if (c.z !== this._tileZoom || !noPruneRange.contains(new Point(c.x, c.y))) {
                this._tiles[key].current = false;
              }
            }
            if (Math.abs(zoom2 - this._tileZoom) > 1) {
              this._setView(center, zoom2);
              return;
            }
            for (var j = tileRange.min.y; j <= tileRange.max.y; j++) {
              for (var i = tileRange.min.x; i <= tileRange.max.x; i++) {
                var coords = new Point(i, j);
                coords.z = this._tileZoom;
                if (!this._isValidTile(coords)) {
                  continue;
                }
                var tile = this._tiles[this._tileCoordsToKey(coords)];
                if (tile) {
                  tile.current = true;
                } else {
                  queue.push(coords);
                }
              }
            }
            queue.sort(function(a, b) {
              return a.distanceTo(tileCenter) - b.distanceTo(tileCenter);
            });
            if (queue.length !== 0) {
              if (!this._loading) {
                this._loading = true;
                this.fire("loading");
              }
              var fragment = document.createDocumentFragment();
              for (i = 0; i < queue.length; i++) {
                this._addTile(queue[i], fragment);
              }
              this._level.el.appendChild(fragment);
            }
          },
          _isValidTile: function(coords) {
            var crs = this._map.options.crs;
            if (!crs.infinite) {
              var bounds = this._globalTileRange;
              if (!crs.wrapLng && (coords.x < bounds.min.x || coords.x > bounds.max.x) || !crs.wrapLat && (coords.y < bounds.min.y || coords.y > bounds.max.y)) {
                return false;
              }
            }
            if (!this.options.bounds) {
              return true;
            }
            var tileBounds = this._tileCoordsToBounds(coords);
            return toLatLngBounds(this.options.bounds).overlaps(tileBounds);
          },
          _keyToBounds: function(key) {
            return this._tileCoordsToBounds(this._keyToTileCoords(key));
          },
          _tileCoordsToNwSe: function(coords) {
            var map2 = this._map, tileSize = this.getTileSize(), nwPoint = coords.scaleBy(tileSize), sePoint = nwPoint.add(tileSize), nw = map2.unproject(nwPoint, coords.z), se = map2.unproject(sePoint, coords.z);
            return [nw, se];
          },
          // converts tile coordinates to its geographical bounds
          _tileCoordsToBounds: function(coords) {
            var bp = this._tileCoordsToNwSe(coords), bounds = new LatLngBounds(bp[0], bp[1]);
            if (!this.options.noWrap) {
              bounds = this._map.wrapLatLngBounds(bounds);
            }
            return bounds;
          },
          // converts tile coordinates to key for the tile cache
          _tileCoordsToKey: function(coords) {
            return coords.x + ":" + coords.y + ":" + coords.z;
          },
          // converts tile cache key to coordinates
          _keyToTileCoords: function(key) {
            var k = key.split(":"), coords = new Point(+k[0], +k[1]);
            coords.z = +k[2];
            return coords;
          },
          _removeTile: function(key) {
            var tile = this._tiles[key];
            if (!tile) {
              return;
            }
            remove(tile.el);
            delete this._tiles[key];
            this.fire("tileunload", {
              tile: tile.el,
              coords: this._keyToTileCoords(key)
            });
          },
          _initTile: function(tile) {
            addClass(tile, "leaflet-tile");
            var tileSize = this.getTileSize();
            tile.style.width = tileSize.x + "px";
            tile.style.height = tileSize.y + "px";
            tile.onselectstart = falseFn;
            tile.onmousemove = falseFn;
            if (Browser.ielt9 && this.options.opacity < 1) {
              setOpacity(tile, this.options.opacity);
            }
          },
          _addTile: function(coords, container) {
            var tilePos = this._getTilePos(coords), key = this._tileCoordsToKey(coords);
            var tile = this.createTile(this._wrapCoords(coords), bind(this._tileReady, this, coords));
            this._initTile(tile);
            if (this.createTile.length < 2) {
              requestAnimFrame(bind(this._tileReady, this, coords, null, tile));
            }
            setPosition(tile, tilePos);
            this._tiles[key] = {
              el: tile,
              coords,
              current: true
            };
            container.appendChild(tile);
            this.fire("tileloadstart", {
              tile,
              coords
            });
          },
          _tileReady: function(coords, err, tile) {
            if (err) {
              this.fire("tileerror", {
                error: err,
                tile,
                coords
              });
            }
            var key = this._tileCoordsToKey(coords);
            tile = this._tiles[key];
            if (!tile) {
              return;
            }
            tile.loaded = +/* @__PURE__ */ new Date();
            if (this._map._fadeAnimated) {
              setOpacity(tile.el, 0);
              cancelAnimFrame(this._fadeFrame);
              this._fadeFrame = requestAnimFrame(this._updateOpacity, this);
            } else {
              tile.active = true;
              this._pruneTiles();
            }
            if (!err) {
              addClass(tile.el, "leaflet-tile-loaded");
              this.fire("tileload", {
                tile: tile.el,
                coords
              });
            }
            if (this._noTilesToLoad()) {
              this._loading = false;
              this.fire("load");
              if (Browser.ielt9 || !this._map._fadeAnimated) {
                requestAnimFrame(this._pruneTiles, this);
              } else {
                setTimeout(bind(this._pruneTiles, this), 250);
              }
            }
          },
          _getTilePos: function(coords) {
            return coords.scaleBy(this.getTileSize()).subtract(this._level.origin);
          },
          _wrapCoords: function(coords) {
            var newCoords = new Point(
              this._wrapX ? wrapNum(coords.x, this._wrapX) : coords.x,
              this._wrapY ? wrapNum(coords.y, this._wrapY) : coords.y
            );
            newCoords.z = coords.z;
            return newCoords;
          },
          _pxBoundsToTileRange: function(bounds) {
            var tileSize = this.getTileSize();
            return new Bounds(
              bounds.min.unscaleBy(tileSize).floor(),
              bounds.max.unscaleBy(tileSize).ceil().subtract([1, 1])
            );
          },
          _noTilesToLoad: function() {
            for (var key in this._tiles) {
              if (!this._tiles[key].loaded) {
                return false;
              }
            }
            return true;
          }
        });
        function gridLayer(options) {
          return new GridLayer(options);
        }
        var TileLayer = GridLayer.extend({
          // @section
          // @aka TileLayer options
          options: {
            // @option minZoom: Number = 0
            // The minimum zoom level down to which this layer will be displayed (inclusive).
            minZoom: 0,
            // @option maxZoom: Number = 18
            // The maximum zoom level up to which this layer will be displayed (inclusive).
            maxZoom: 18,
            // @option subdomains: String|String[] = 'abc'
            // Subdomains of the tile service. Can be passed in the form of one string (where each letter is a subdomain name) or an array of strings.
            subdomains: "abc",
            // @option errorTileUrl: String = ''
            // URL to the tile image to show in place of the tile that failed to load.
            errorTileUrl: "",
            // @option zoomOffset: Number = 0
            // The zoom number used in tile URLs will be offset with this value.
            zoomOffset: 0,
            // @option tms: Boolean = false
            // If `true`, inverses Y axis numbering for tiles (turn this on for [TMS](https://en.wikipedia.org/wiki/Tile_Map_Service) services).
            tms: false,
            // @option zoomReverse: Boolean = false
            // If set to true, the zoom number used in tile URLs will be reversed (`maxZoom - zoom` instead of `zoom`)
            zoomReverse: false,
            // @option detectRetina: Boolean = false
            // If `true` and user is on a retina display, it will request four tiles of half the specified size and a bigger zoom level in place of one to utilize the high resolution.
            detectRetina: false,
            // @option crossOrigin: Boolean|String = false
            // Whether the crossOrigin attribute will be added to the tiles.
            // If a String is provided, all tiles will have their crossOrigin attribute set to the String provided. This is needed if you want to access tile pixel data.
            // Refer to [CORS Settings](https://developer.mozilla.org/en-US/docs/Web/HTML/CORS_settings_attributes) for valid String values.
            crossOrigin: false,
            // @option referrerPolicy: Boolean|String = false
            // Whether the referrerPolicy attribute will be added to the tiles.
            // If a String is provided, all tiles will have their referrerPolicy attribute set to the String provided.
            // This may be needed if your map's rendering context has a strict default but your tile provider expects a valid referrer
            // (e.g. to validate an API token).
            // Refer to [HTMLImageElement.referrerPolicy](https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/referrerPolicy) for valid String values.
            referrerPolicy: false
          },
          initialize: function(url, options) {
            this._url = url;
            options = setOptions(this, options);
            if (options.detectRetina && Browser.retina && options.maxZoom > 0) {
              options.tileSize = Math.floor(options.tileSize / 2);
              if (!options.zoomReverse) {
                options.zoomOffset++;
                options.maxZoom = Math.max(options.minZoom, options.maxZoom - 1);
              } else {
                options.zoomOffset--;
                options.minZoom = Math.min(options.maxZoom, options.minZoom + 1);
              }
              options.minZoom = Math.max(0, options.minZoom);
            } else if (!options.zoomReverse) {
              options.maxZoom = Math.max(options.minZoom, options.maxZoom);
            } else {
              options.minZoom = Math.min(options.maxZoom, options.minZoom);
            }
            if (typeof options.subdomains === "string") {
              options.subdomains = options.subdomains.split("");
            }
            this.on("tileunload", this._onTileRemove);
          },
          // @method setUrl(url: String, noRedraw?: Boolean): this
          // Updates the layer's URL template and redraws it (unless `noRedraw` is set to `true`).
          // If the URL does not change, the layer will not be redrawn unless
          // the noRedraw parameter is set to false.
          setUrl: function(url, noRedraw) {
            if (this._url === url && noRedraw === void 0) {
              noRedraw = true;
            }
            this._url = url;
            if (!noRedraw) {
              this.redraw();
            }
            return this;
          },
          // @method createTile(coords: Object, done?: Function): HTMLElement
          // Called only internally, overrides GridLayer's [`createTile()`](#gridlayer-createtile)
          // to return an `<img>` HTML element with the appropriate image URL given `coords`. The `done`
          // callback is called when the tile has been loaded.
          createTile: function(coords, done) {
            var tile = document.createElement("img");
            on(tile, "load", bind(this._tileOnLoad, this, done, tile));
            on(tile, "error", bind(this._tileOnError, this, done, tile));
            if (this.options.crossOrigin || this.options.crossOrigin === "") {
              tile.crossOrigin = this.options.crossOrigin === true ? "" : this.options.crossOrigin;
            }
            if (typeof this.options.referrerPolicy === "string") {
              tile.referrerPolicy = this.options.referrerPolicy;
            }
            tile.alt = "";
            tile.src = this.getTileUrl(coords);
            return tile;
          },
          // @section Extension methods
          // @uninheritable
          // Layers extending `TileLayer` might reimplement the following method.
          // @method getTileUrl(coords: Object): String
          // Called only internally, returns the URL for a tile given its coordinates.
          // Classes extending `TileLayer` can override this function to provide custom tile URL naming schemes.
          getTileUrl: function(coords) {
            var data = {
              r: Browser.retina ? "@2x" : "",
              s: this._getSubdomain(coords),
              x: coords.x,
              y: coords.y,
              z: this._getZoomForUrl()
            };
            if (this._map && !this._map.options.crs.infinite) {
              var invertedY = this._globalTileRange.max.y - coords.y;
              if (this.options.tms) {
                data["y"] = invertedY;
              }
              data["-y"] = invertedY;
            }
            return template(this._url, extend(data, this.options));
          },
          _tileOnLoad: function(done, tile) {
            if (Browser.ielt9) {
              setTimeout(bind(done, this, null, tile), 0);
            } else {
              done(null, tile);
            }
          },
          _tileOnError: function(done, tile, e) {
            var errorUrl = this.options.errorTileUrl;
            if (errorUrl && tile.getAttribute("src") !== errorUrl) {
              tile.src = errorUrl;
            }
            done(e, tile);
          },
          _onTileRemove: function(e) {
            e.tile.onload = null;
          },
          _getZoomForUrl: function() {
            var zoom2 = this._tileZoom, maxZoom = this.options.maxZoom, zoomReverse = this.options.zoomReverse, zoomOffset = this.options.zoomOffset;
            if (zoomReverse) {
              zoom2 = maxZoom - zoom2;
            }
            return zoom2 + zoomOffset;
          },
          _getSubdomain: function(tilePoint) {
            var index2 = Math.abs(tilePoint.x + tilePoint.y) % this.options.subdomains.length;
            return this.options.subdomains[index2];
          },
          // stops loading all tiles in the background layer
          _abortLoading: function() {
            var i, tile;
            for (i in this._tiles) {
              if (this._tiles[i].coords.z !== this._tileZoom) {
                tile = this._tiles[i].el;
                tile.onload = falseFn;
                tile.onerror = falseFn;
                if (!tile.complete) {
                  tile.src = emptyImageUrl;
                  var coords = this._tiles[i].coords;
                  remove(tile);
                  delete this._tiles[i];
                  this.fire("tileabort", {
                    tile,
                    coords
                  });
                }
              }
            }
          },
          _removeTile: function(key) {
            var tile = this._tiles[key];
            if (!tile) {
              return;
            }
            tile.el.setAttribute("src", emptyImageUrl);
            return GridLayer.prototype._removeTile.call(this, key);
          },
          _tileReady: function(coords, err, tile) {
            if (!this._map || tile && tile.getAttribute("src") === emptyImageUrl) {
              return;
            }
            return GridLayer.prototype._tileReady.call(this, coords, err, tile);
          }
        });
        function tileLayer2(url, options) {
          return new TileLayer(url, options);
        }
        var TileLayerWMS = TileLayer.extend({
          // @section
          // @aka TileLayer.WMS options
          // If any custom options not documented here are used, they will be sent to the
          // WMS server as extra parameters in each request URL. This can be useful for
          // [non-standard vendor WMS parameters](https://docs.geoserver.org/stable/en/user/services/wms/vendor.html).
          defaultWmsParams: {
            service: "WMS",
            request: "GetMap",
            // @option layers: String = ''
            // **(required)** Comma-separated list of WMS layers to show.
            layers: "",
            // @option styles: String = ''
            // Comma-separated list of WMS styles.
            styles: "",
            // @option format: String = 'image/jpeg'
            // WMS image format (use `'image/png'` for layers with transparency).
            format: "image/jpeg",
            // @option transparent: Boolean = false
            // If `true`, the WMS service will return images with transparency.
            transparent: false,
            // @option version: String = '1.1.1'
            // Version of the WMS service to use
            version: "1.1.1"
          },
          options: {
            // @option crs: CRS = null
            // Coordinate Reference System to use for the WMS requests, defaults to
            // map CRS. Don't change this if you're not sure what it means.
            crs: null,
            // @option uppercase: Boolean = false
            // If `true`, WMS request parameter keys will be uppercase.
            uppercase: false
          },
          initialize: function(url, options) {
            this._url = url;
            var wmsParams = extend({}, this.defaultWmsParams);
            for (var i in options) {
              if (!(i in this.options)) {
                wmsParams[i] = options[i];
              }
            }
            options = setOptions(this, options);
            var realRetina = options.detectRetina && Browser.retina ? 2 : 1;
            var tileSize = this.getTileSize();
            wmsParams.width = tileSize.x * realRetina;
            wmsParams.height = tileSize.y * realRetina;
            this.wmsParams = wmsParams;
          },
          onAdd: function(map2) {
            this._crs = this.options.crs || map2.options.crs;
            this._wmsVersion = parseFloat(this.wmsParams.version);
            var projectionKey = this._wmsVersion >= 1.3 ? "crs" : "srs";
            this.wmsParams[projectionKey] = this._crs.code;
            TileLayer.prototype.onAdd.call(this, map2);
          },
          getTileUrl: function(coords) {
            var tileBounds = this._tileCoordsToNwSe(coords), crs = this._crs, bounds = toBounds(crs.project(tileBounds[0]), crs.project(tileBounds[1])), min = bounds.min, max = bounds.max, bbox = (this._wmsVersion >= 1.3 && this._crs === EPSG4326 ? [min.y, min.x, max.y, max.x] : [min.x, min.y, max.x, max.y]).join(","), url = TileLayer.prototype.getTileUrl.call(this, coords);
            return url + getParamString(this.wmsParams, url, this.options.uppercase) + (this.options.uppercase ? "&BBOX=" : "&bbox=") + bbox;
          },
          // @method setParams(params: Object, noRedraw?: Boolean): this
          // Merges an object with the new parameters and re-requests tiles on the current screen (unless `noRedraw` was set to true).
          setParams: function(params, noRedraw) {
            extend(this.wmsParams, params);
            if (!noRedraw) {
              this.redraw();
            }
            return this;
          }
        });
        function tileLayerWMS(url, options) {
          return new TileLayerWMS(url, options);
        }
        TileLayer.WMS = TileLayerWMS;
        tileLayer2.wms = tileLayerWMS;
        var Renderer = Layer.extend({
          // @section
          // @aka Renderer options
          options: {
            // @option padding: Number = 0.1
            // How much to extend the clip area around the map view (relative to its size)
            // e.g. 0.1 would be 10% of map view in each direction
            padding: 0.1
          },
          initialize: function(options) {
            setOptions(this, options);
            stamp(this);
            this._layers = this._layers || {};
          },
          onAdd: function() {
            if (!this._container) {
              this._initContainer();
              addClass(this._container, "leaflet-zoom-animated");
            }
            this.getPane().appendChild(this._container);
            this._update();
            this.on("update", this._updatePaths, this);
          },
          onRemove: function() {
            this.off("update", this._updatePaths, this);
            this._destroyContainer();
          },
          getEvents: function() {
            var events = {
              viewreset: this._reset,
              zoom: this._onZoom,
              moveend: this._update,
              zoomend: this._onZoomEnd
            };
            if (this._zoomAnimated) {
              events.zoomanim = this._onAnimZoom;
            }
            return events;
          },
          _onAnimZoom: function(ev) {
            this._updateTransform(ev.center, ev.zoom);
          },
          _onZoom: function() {
            this._updateTransform(this._map.getCenter(), this._map.getZoom());
          },
          _updateTransform: function(center, zoom2) {
            var scale2 = this._map.getZoomScale(zoom2, this._zoom), viewHalf = this._map.getSize().multiplyBy(0.5 + this.options.padding), currentCenterPoint = this._map.project(this._center, zoom2), topLeftOffset = viewHalf.multiplyBy(-scale2).add(currentCenterPoint).subtract(this._map._getNewPixelOrigin(center, zoom2));
            if (Browser.any3d) {
              setTransform(this._container, topLeftOffset, scale2);
            } else {
              setPosition(this._container, topLeftOffset);
            }
          },
          _reset: function() {
            this._update();
            this._updateTransform(this._center, this._zoom);
            for (var id in this._layers) {
              this._layers[id]._reset();
            }
          },
          _onZoomEnd: function() {
            for (var id in this._layers) {
              this._layers[id]._project();
            }
          },
          _updatePaths: function() {
            for (var id in this._layers) {
              this._layers[id]._update();
            }
          },
          _update: function() {
            var p = this.options.padding, size = this._map.getSize(), min = this._map.containerPointToLayerPoint(size.multiplyBy(-p)).round();
            this._bounds = new Bounds(min, min.add(size.multiplyBy(1 + p * 2)).round());
            this._center = this._map.getCenter();
            this._zoom = this._map.getZoom();
          }
        });
        var Canvas = Renderer.extend({
          // @section
          // @aka Canvas options
          options: {
            // @option tolerance: Number = 0
            // How much to extend the click tolerance around a path/object on the map.
            tolerance: 0
          },
          getEvents: function() {
            var events = Renderer.prototype.getEvents.call(this);
            events.viewprereset = this._onViewPreReset;
            return events;
          },
          _onViewPreReset: function() {
            this._postponeUpdatePaths = true;
          },
          onAdd: function() {
            Renderer.prototype.onAdd.call(this);
            this._draw();
          },
          _initContainer: function() {
            var container = this._container = document.createElement("canvas");
            on(container, "mousemove", this._onMouseMove, this);
            on(container, "click dblclick mousedown mouseup contextmenu", this._onClick, this);
            on(container, "mouseout", this._handleMouseOut, this);
            container["_leaflet_disable_events"] = true;
            this._ctx = container.getContext("2d");
          },
          _destroyContainer: function() {
            cancelAnimFrame(this._redrawRequest);
            delete this._ctx;
            remove(this._container);
            off(this._container);
            delete this._container;
          },
          _updatePaths: function() {
            if (this._postponeUpdatePaths) {
              return;
            }
            var layer;
            this._redrawBounds = null;
            for (var id in this._layers) {
              layer = this._layers[id];
              layer._update();
            }
            this._redraw();
          },
          _update: function() {
            if (this._map._animatingZoom && this._bounds) {
              return;
            }
            Renderer.prototype._update.call(this);
            var b = this._bounds, container = this._container, size = b.getSize(), m = Browser.retina ? 2 : 1;
            setPosition(container, b.min);
            container.width = m * size.x;
            container.height = m * size.y;
            container.style.width = size.x + "px";
            container.style.height = size.y + "px";
            if (Browser.retina) {
              this._ctx.scale(2, 2);
            }
            this._ctx.translate(-b.min.x, -b.min.y);
            this.fire("update");
          },
          _reset: function() {
            Renderer.prototype._reset.call(this);
            if (this._postponeUpdatePaths) {
              this._postponeUpdatePaths = false;
              this._updatePaths();
            }
          },
          _initPath: function(layer) {
            this._updateDashArray(layer);
            this._layers[stamp(layer)] = layer;
            var order = layer._order = {
              layer,
              prev: this._drawLast,
              next: null
            };
            if (this._drawLast) {
              this._drawLast.next = order;
            }
            this._drawLast = order;
            this._drawFirst = this._drawFirst || this._drawLast;
          },
          _addPath: function(layer) {
            this._requestRedraw(layer);
          },
          _removePath: function(layer) {
            var order = layer._order;
            var next = order.next;
            var prev = order.prev;
            if (next) {
              next.prev = prev;
            } else {
              this._drawLast = prev;
            }
            if (prev) {
              prev.next = next;
            } else {
              this._drawFirst = next;
            }
            delete layer._order;
            delete this._layers[stamp(layer)];
            this._requestRedraw(layer);
          },
          _updatePath: function(layer) {
            this._extendRedrawBounds(layer);
            layer._project();
            layer._update();
            this._requestRedraw(layer);
          },
          _updateStyle: function(layer) {
            this._updateDashArray(layer);
            this._requestRedraw(layer);
          },
          _updateDashArray: function(layer) {
            if (typeof layer.options.dashArray === "string") {
              var parts = layer.options.dashArray.split(/[, ]+/), dashArray = [], dashValue, i;
              for (i = 0; i < parts.length; i++) {
                dashValue = Number(parts[i]);
                if (isNaN(dashValue)) {
                  return;
                }
                dashArray.push(dashValue);
              }
              layer.options._dashArray = dashArray;
            } else {
              layer.options._dashArray = layer.options.dashArray;
            }
          },
          _requestRedraw: function(layer) {
            if (!this._map) {
              return;
            }
            this._extendRedrawBounds(layer);
            this._redrawRequest = this._redrawRequest || requestAnimFrame(this._redraw, this);
          },
          _extendRedrawBounds: function(layer) {
            if (layer._pxBounds) {
              var padding = (layer.options.weight || 0) + 1;
              this._redrawBounds = this._redrawBounds || new Bounds();
              this._redrawBounds.extend(layer._pxBounds.min.subtract([padding, padding]));
              this._redrawBounds.extend(layer._pxBounds.max.add([padding, padding]));
            }
          },
          _redraw: function() {
            this._redrawRequest = null;
            if (this._redrawBounds) {
              this._redrawBounds.min._floor();
              this._redrawBounds.max._ceil();
            }
            this._clear();
            this._draw();
            this._redrawBounds = null;
          },
          _clear: function() {
            var bounds = this._redrawBounds;
            if (bounds) {
              var size = bounds.getSize();
              this._ctx.clearRect(bounds.min.x, bounds.min.y, size.x, size.y);
            } else {
              this._ctx.save();
              this._ctx.setTransform(1, 0, 0, 1, 0, 0);
              this._ctx.clearRect(0, 0, this._container.width, this._container.height);
              this._ctx.restore();
            }
          },
          _draw: function() {
            var layer, bounds = this._redrawBounds;
            this._ctx.save();
            if (bounds) {
              var size = bounds.getSize();
              this._ctx.beginPath();
              this._ctx.rect(bounds.min.x, bounds.min.y, size.x, size.y);
              this._ctx.clip();
            }
            this._drawing = true;
            for (var order = this._drawFirst; order; order = order.next) {
              layer = order.layer;
              if (!bounds || layer._pxBounds && layer._pxBounds.intersects(bounds)) {
                layer._updatePath();
              }
            }
            this._drawing = false;
            this._ctx.restore();
          },
          _updatePoly: function(layer, closed) {
            if (!this._drawing) {
              return;
            }
            var i, j, len2, p, parts = layer._parts, len = parts.length, ctx = this._ctx;
            if (!len) {
              return;
            }
            ctx.beginPath();
            for (i = 0; i < len; i++) {
              for (j = 0, len2 = parts[i].length; j < len2; j++) {
                p = parts[i][j];
                ctx[j ? "lineTo" : "moveTo"](p.x, p.y);
              }
              if (closed) {
                ctx.closePath();
              }
            }
            this._fillStroke(ctx, layer);
          },
          _updateCircle: function(layer) {
            if (!this._drawing || layer._empty()) {
              return;
            }
            var p = layer._point, ctx = this._ctx, r = Math.max(Math.round(layer._radius), 1), s = (Math.max(Math.round(layer._radiusY), 1) || r) / r;
            if (s !== 1) {
              ctx.save();
              ctx.scale(1, s);
            }
            ctx.beginPath();
            ctx.arc(p.x, p.y / s, r, 0, Math.PI * 2, false);
            if (s !== 1) {
              ctx.restore();
            }
            this._fillStroke(ctx, layer);
          },
          _fillStroke: function(ctx, layer) {
            var options = layer.options;
            if (options.fill) {
              ctx.globalAlpha = options.fillOpacity;
              ctx.fillStyle = options.fillColor || options.color;
              ctx.fill(options.fillRule || "evenodd");
            }
            if (options.stroke && options.weight !== 0) {
              if (ctx.setLineDash) {
                ctx.setLineDash(layer.options && layer.options._dashArray || []);
              }
              ctx.globalAlpha = options.opacity;
              ctx.lineWidth = options.weight;
              ctx.strokeStyle = options.color;
              ctx.lineCap = options.lineCap;
              ctx.lineJoin = options.lineJoin;
              ctx.stroke();
            }
          },
          // Canvas obviously doesn't have mouse events for individual drawn objects,
          // so we emulate that by calculating what's under the mouse on mousemove/click manually
          _onClick: function(e) {
            var point = this._map.mouseEventToLayerPoint(e), layer, clickedLayer;
            for (var order = this._drawFirst; order; order = order.next) {
              layer = order.layer;
              if (layer.options.interactive && layer._containsPoint(point)) {
                if (!(e.type === "click" || e.type === "preclick") || !this._map._draggableMoved(layer)) {
                  clickedLayer = layer;
                }
              }
            }
            this._fireEvent(clickedLayer ? [clickedLayer] : false, e);
          },
          _onMouseMove: function(e) {
            if (!this._map || this._map.dragging.moving() || this._map._animatingZoom) {
              return;
            }
            var point = this._map.mouseEventToLayerPoint(e);
            this._handleMouseHover(e, point);
          },
          _handleMouseOut: function(e) {
            var layer = this._hoveredLayer;
            if (layer) {
              removeClass(this._container, "leaflet-interactive");
              this._fireEvent([layer], e, "mouseout");
              this._hoveredLayer = null;
              this._mouseHoverThrottled = false;
            }
          },
          _handleMouseHover: function(e, point) {
            if (this._mouseHoverThrottled) {
              return;
            }
            var layer, candidateHoveredLayer;
            for (var order = this._drawFirst; order; order = order.next) {
              layer = order.layer;
              if (layer.options.interactive && layer._containsPoint(point)) {
                candidateHoveredLayer = layer;
              }
            }
            if (candidateHoveredLayer !== this._hoveredLayer) {
              this._handleMouseOut(e);
              if (candidateHoveredLayer) {
                addClass(this._container, "leaflet-interactive");
                this._fireEvent([candidateHoveredLayer], e, "mouseover");
                this._hoveredLayer = candidateHoveredLayer;
              }
            }
            this._fireEvent(this._hoveredLayer ? [this._hoveredLayer] : false, e);
            this._mouseHoverThrottled = true;
            setTimeout(bind(function() {
              this._mouseHoverThrottled = false;
            }, this), 32);
          },
          _fireEvent: function(layers2, e, type) {
            this._map._fireDOMEvent(e, type || e.type, layers2);
          },
          _bringToFront: function(layer) {
            var order = layer._order;
            if (!order) {
              return;
            }
            var next = order.next;
            var prev = order.prev;
            if (next) {
              next.prev = prev;
            } else {
              return;
            }
            if (prev) {
              prev.next = next;
            } else if (next) {
              this._drawFirst = next;
            }
            order.prev = this._drawLast;
            this._drawLast.next = order;
            order.next = null;
            this._drawLast = order;
            this._requestRedraw(layer);
          },
          _bringToBack: function(layer) {
            var order = layer._order;
            if (!order) {
              return;
            }
            var next = order.next;
            var prev = order.prev;
            if (prev) {
              prev.next = next;
            } else {
              return;
            }
            if (next) {
              next.prev = prev;
            } else if (prev) {
              this._drawLast = prev;
            }
            order.prev = null;
            order.next = this._drawFirst;
            this._drawFirst.prev = order;
            this._drawFirst = order;
            this._requestRedraw(layer);
          }
        });
        function canvas(options) {
          return Browser.canvas ? new Canvas(options) : null;
        }
        var vmlCreate = (function() {
          try {
            document.namespaces.add("lvml", "urn:schemas-microsoft-com:vml");
            return function(name) {
              return document.createElement("<lvml:" + name + ' class="lvml">');
            };
          } catch (e) {
          }
          return function(name) {
            return document.createElement("<" + name + ' xmlns="urn:schemas-microsoft.com:vml" class="lvml">');
          };
        })();
        var vmlMixin = {
          _initContainer: function() {
            this._container = create$1("div", "leaflet-vml-container");
          },
          _update: function() {
            if (this._map._animatingZoom) {
              return;
            }
            Renderer.prototype._update.call(this);
            this.fire("update");
          },
          _initPath: function(layer) {
            var container = layer._container = vmlCreate("shape");
            addClass(container, "leaflet-vml-shape " + (this.options.className || ""));
            container.coordsize = "1 1";
            layer._path = vmlCreate("path");
            container.appendChild(layer._path);
            this._updateStyle(layer);
            this._layers[stamp(layer)] = layer;
          },
          _addPath: function(layer) {
            var container = layer._container;
            this._container.appendChild(container);
            if (layer.options.interactive) {
              layer.addInteractiveTarget(container);
            }
          },
          _removePath: function(layer) {
            var container = layer._container;
            remove(container);
            layer.removeInteractiveTarget(container);
            delete this._layers[stamp(layer)];
          },
          _updateStyle: function(layer) {
            var stroke = layer._stroke, fill = layer._fill, options = layer.options, container = layer._container;
            container.stroked = !!options.stroke;
            container.filled = !!options.fill;
            if (options.stroke) {
              if (!stroke) {
                stroke = layer._stroke = vmlCreate("stroke");
              }
              container.appendChild(stroke);
              stroke.weight = options.weight + "px";
              stroke.color = options.color;
              stroke.opacity = options.opacity;
              if (options.dashArray) {
                stroke.dashStyle = isArray(options.dashArray) ? options.dashArray.join(" ") : options.dashArray.replace(/( *, *)/g, " ");
              } else {
                stroke.dashStyle = "";
              }
              stroke.endcap = options.lineCap.replace("butt", "flat");
              stroke.joinstyle = options.lineJoin;
            } else if (stroke) {
              container.removeChild(stroke);
              layer._stroke = null;
            }
            if (options.fill) {
              if (!fill) {
                fill = layer._fill = vmlCreate("fill");
              }
              container.appendChild(fill);
              fill.color = options.fillColor || options.color;
              fill.opacity = options.fillOpacity;
            } else if (fill) {
              container.removeChild(fill);
              layer._fill = null;
            }
          },
          _updateCircle: function(layer) {
            var p = layer._point.round(), r = Math.round(layer._radius), r2 = Math.round(layer._radiusY || r);
            this._setPath(layer, layer._empty() ? "M0 0" : "AL " + p.x + "," + p.y + " " + r + "," + r2 + " 0," + 65535 * 360);
          },
          _setPath: function(layer, path) {
            layer._path.v = path;
          },
          _bringToFront: function(layer) {
            toFront(layer._container);
          },
          _bringToBack: function(layer) {
            toBack(layer._container);
          }
        };
        var create = Browser.vml ? vmlCreate : svgCreate;
        var SVG = Renderer.extend({
          _initContainer: function() {
            this._container = create("svg");
            this._container.setAttribute("pointer-events", "none");
            this._rootGroup = create("g");
            this._container.appendChild(this._rootGroup);
          },
          _destroyContainer: function() {
            remove(this._container);
            off(this._container);
            delete this._container;
            delete this._rootGroup;
            delete this._svgSize;
          },
          _update: function() {
            if (this._map._animatingZoom && this._bounds) {
              return;
            }
            Renderer.prototype._update.call(this);
            var b = this._bounds, size = b.getSize(), container = this._container;
            if (!this._svgSize || !this._svgSize.equals(size)) {
              this._svgSize = size;
              container.setAttribute("width", size.x);
              container.setAttribute("height", size.y);
            }
            setPosition(container, b.min);
            container.setAttribute("viewBox", [b.min.x, b.min.y, size.x, size.y].join(" "));
            this.fire("update");
          },
          // methods below are called by vector layers implementations
          _initPath: function(layer) {
            var path = layer._path = create("path");
            if (layer.options.className) {
              addClass(path, layer.options.className);
            }
            if (layer.options.interactive) {
              addClass(path, "leaflet-interactive");
            }
            this._updateStyle(layer);
            this._layers[stamp(layer)] = layer;
          },
          _addPath: function(layer) {
            if (!this._rootGroup) {
              this._initContainer();
            }
            this._rootGroup.appendChild(layer._path);
            layer.addInteractiveTarget(layer._path);
          },
          _removePath: function(layer) {
            remove(layer._path);
            layer.removeInteractiveTarget(layer._path);
            delete this._layers[stamp(layer)];
          },
          _updatePath: function(layer) {
            layer._project();
            layer._update();
          },
          _updateStyle: function(layer) {
            var path = layer._path, options = layer.options;
            if (!path) {
              return;
            }
            if (options.stroke) {
              path.setAttribute("stroke", options.color);
              path.setAttribute("stroke-opacity", options.opacity);
              path.setAttribute("stroke-width", options.weight);
              path.setAttribute("stroke-linecap", options.lineCap);
              path.setAttribute("stroke-linejoin", options.lineJoin);
              if (options.dashArray) {
                path.setAttribute("stroke-dasharray", options.dashArray);
              } else {
                path.removeAttribute("stroke-dasharray");
              }
              if (options.dashOffset) {
                path.setAttribute("stroke-dashoffset", options.dashOffset);
              } else {
                path.removeAttribute("stroke-dashoffset");
              }
            } else {
              path.setAttribute("stroke", "none");
            }
            if (options.fill) {
              path.setAttribute("fill", options.fillColor || options.color);
              path.setAttribute("fill-opacity", options.fillOpacity);
              path.setAttribute("fill-rule", options.fillRule || "evenodd");
            } else {
              path.setAttribute("fill", "none");
            }
          },
          _updatePoly: function(layer, closed) {
            this._setPath(layer, pointsToPath(layer._parts, closed));
          },
          _updateCircle: function(layer) {
            var p = layer._point, r = Math.max(Math.round(layer._radius), 1), r2 = Math.max(Math.round(layer._radiusY), 1) || r, arc = "a" + r + "," + r2 + " 0 1,0 ";
            var d = layer._empty() ? "M0 0" : "M" + (p.x - r) + "," + p.y + arc + r * 2 + ",0 " + arc + -r * 2 + ",0 ";
            this._setPath(layer, d);
          },
          _setPath: function(layer, path) {
            layer._path.setAttribute("d", path);
          },
          // SVG does not have the concept of zIndex so we resort to changing the DOM order of elements
          _bringToFront: function(layer) {
            toFront(layer._path);
          },
          _bringToBack: function(layer) {
            toBack(layer._path);
          }
        });
        if (Browser.vml) {
          SVG.include(vmlMixin);
        }
        function svg(options) {
          return Browser.svg || Browser.vml ? new SVG(options) : null;
        }
        Map2.include({
          // @namespace Map; @method getRenderer(layer: Path): Renderer
          // Returns the instance of `Renderer` that should be used to render the given
          // `Path`. It will ensure that the `renderer` options of the map and paths
          // are respected, and that the renderers do exist on the map.
          getRenderer: function(layer) {
            var renderer = layer.options.renderer || this._getPaneRenderer(layer.options.pane) || this.options.renderer || this._renderer;
            if (!renderer) {
              renderer = this._renderer = this._createRenderer();
            }
            if (!this.hasLayer(renderer)) {
              this.addLayer(renderer);
            }
            return renderer;
          },
          _getPaneRenderer: function(name) {
            if (name === "overlayPane" || name === void 0) {
              return false;
            }
            var renderer = this._paneRenderers[name];
            if (renderer === void 0) {
              renderer = this._createRenderer({ pane: name });
              this._paneRenderers[name] = renderer;
            }
            return renderer;
          },
          _createRenderer: function(options) {
            return this.options.preferCanvas && canvas(options) || svg(options);
          }
        });
        var Rectangle = Polygon.extend({
          initialize: function(latLngBounds2, options) {
            Polygon.prototype.initialize.call(this, this._boundsToLatLngs(latLngBounds2), options);
          },
          // @method setBounds(latLngBounds: LatLngBounds): this
          // Redraws the rectangle with the passed bounds.
          setBounds: function(latLngBounds2) {
            return this.setLatLngs(this._boundsToLatLngs(latLngBounds2));
          },
          _boundsToLatLngs: function(latLngBounds2) {
            latLngBounds2 = toLatLngBounds(latLngBounds2);
            return [
              latLngBounds2.getSouthWest(),
              latLngBounds2.getNorthWest(),
              latLngBounds2.getNorthEast(),
              latLngBounds2.getSouthEast()
            ];
          }
        });
        function rectangle(latLngBounds2, options) {
          return new Rectangle(latLngBounds2, options);
        }
        SVG.create = create;
        SVG.pointsToPath = pointsToPath;
        GeoJSON.geometryToLayer = geometryToLayer;
        GeoJSON.coordsToLatLng = coordsToLatLng;
        GeoJSON.coordsToLatLngs = coordsToLatLngs;
        GeoJSON.latLngToCoords = latLngToCoords;
        GeoJSON.latLngsToCoords = latLngsToCoords;
        GeoJSON.getFeature = getFeature;
        GeoJSON.asFeature = asFeature;
        Map2.mergeOptions({
          // @option boxZoom: Boolean = true
          // Whether the map can be zoomed to a rectangular area specified by
          // dragging the mouse while pressing the shift key.
          boxZoom: true
        });
        var BoxZoom = Handler.extend({
          initialize: function(map2) {
            this._map = map2;
            this._container = map2._container;
            this._pane = map2._panes.overlayPane;
            this._resetStateTimeout = 0;
            map2.on("unload", this._destroy, this);
          },
          addHooks: function() {
            on(this._container, "mousedown", this._onMouseDown, this);
          },
          removeHooks: function() {
            off(this._container, "mousedown", this._onMouseDown, this);
          },
          moved: function() {
            return this._moved;
          },
          _destroy: function() {
            remove(this._pane);
            delete this._pane;
          },
          _resetState: function() {
            this._resetStateTimeout = 0;
            this._moved = false;
          },
          _clearDeferredResetState: function() {
            if (this._resetStateTimeout !== 0) {
              clearTimeout(this._resetStateTimeout);
              this._resetStateTimeout = 0;
            }
          },
          _onMouseDown: function(e) {
            if (!e.shiftKey || e.which !== 1 && e.button !== 1) {
              return false;
            }
            this._clearDeferredResetState();
            this._resetState();
            disableTextSelection();
            disableImageDrag();
            this._startPoint = this._map.mouseEventToContainerPoint(e);
            on(document, {
              contextmenu: stop,
              mousemove: this._onMouseMove,
              mouseup: this._onMouseUp,
              keydown: this._onKeyDown
            }, this);
          },
          _onMouseMove: function(e) {
            if (!this._moved) {
              this._moved = true;
              this._box = create$1("div", "leaflet-zoom-box", this._container);
              addClass(this._container, "leaflet-crosshair");
              this._map.fire("boxzoomstart");
            }
            this._point = this._map.mouseEventToContainerPoint(e);
            var bounds = new Bounds(this._point, this._startPoint), size = bounds.getSize();
            setPosition(this._box, bounds.min);
            this._box.style.width = size.x + "px";
            this._box.style.height = size.y + "px";
          },
          _finish: function() {
            if (this._moved) {
              remove(this._box);
              removeClass(this._container, "leaflet-crosshair");
            }
            enableTextSelection();
            enableImageDrag();
            off(document, {
              contextmenu: stop,
              mousemove: this._onMouseMove,
              mouseup: this._onMouseUp,
              keydown: this._onKeyDown
            }, this);
          },
          _onMouseUp: function(e) {
            if (e.which !== 1 && e.button !== 1) {
              return;
            }
            this._finish();
            if (!this._moved) {
              return;
            }
            this._clearDeferredResetState();
            this._resetStateTimeout = setTimeout(bind(this._resetState, this), 0);
            var bounds = new LatLngBounds(
              this._map.containerPointToLatLng(this._startPoint),
              this._map.containerPointToLatLng(this._point)
            );
            this._map.fitBounds(bounds).fire("boxzoomend", { boxZoomBounds: bounds });
          },
          _onKeyDown: function(e) {
            if (e.keyCode === 27) {
              this._finish();
              this._clearDeferredResetState();
              this._resetState();
            }
          }
        });
        Map2.addInitHook("addHandler", "boxZoom", BoxZoom);
        Map2.mergeOptions({
          // @option doubleClickZoom: Boolean|String = true
          // Whether the map can be zoomed in by double clicking on it and
          // zoomed out by double clicking while holding shift. If passed
          // `'center'`, double-click zoom will zoom to the center of the
          //  view regardless of where the mouse was.
          doubleClickZoom: true
        });
        var DoubleClickZoom = Handler.extend({
          addHooks: function() {
            this._map.on("dblclick", this._onDoubleClick, this);
          },
          removeHooks: function() {
            this._map.off("dblclick", this._onDoubleClick, this);
          },
          _onDoubleClick: function(e) {
            var map2 = this._map, oldZoom = map2.getZoom(), delta = map2.options.zoomDelta, zoom2 = e.originalEvent.shiftKey ? oldZoom - delta : oldZoom + delta;
            if (map2.options.doubleClickZoom === "center") {
              map2.setZoom(zoom2);
            } else {
              map2.setZoomAround(e.containerPoint, zoom2);
            }
          }
        });
        Map2.addInitHook("addHandler", "doubleClickZoom", DoubleClickZoom);
        Map2.mergeOptions({
          // @option dragging: Boolean = true
          // Whether the map is draggable with mouse/touch or not.
          dragging: true,
          // @section Panning Inertia Options
          // @option inertia: Boolean = *
          // If enabled, panning of the map will have an inertia effect where
          // the map builds momentum while dragging and continues moving in
          // the same direction for some time. Feels especially nice on touch
          // devices. Enabled by default.
          inertia: true,
          // @option inertiaDeceleration: Number = 3000
          // The rate with which the inertial movement slows down, in pixels/second².
          inertiaDeceleration: 3400,
          // px/s^2
          // @option inertiaMaxSpeed: Number = Infinity
          // Max speed of the inertial movement, in pixels/second.
          inertiaMaxSpeed: Infinity,
          // px/s
          // @option easeLinearity: Number = 0.2
          easeLinearity: 0.2,
          // TODO refactor, move to CRS
          // @option worldCopyJump: Boolean = false
          // With this option enabled, the map tracks when you pan to another "copy"
          // of the world and seamlessly jumps to the original one so that all overlays
          // like markers and vector layers are still visible.
          worldCopyJump: false,
          // @option maxBoundsViscosity: Number = 0.0
          // If `maxBounds` is set, this option will control how solid the bounds
          // are when dragging the map around. The default value of `0.0` allows the
          // user to drag outside the bounds at normal speed, higher values will
          // slow down map dragging outside bounds, and `1.0` makes the bounds fully
          // solid, preventing the user from dragging outside the bounds.
          maxBoundsViscosity: 0
        });
        var Drag = Handler.extend({
          addHooks: function() {
            if (!this._draggable) {
              var map2 = this._map;
              this._draggable = new Draggable(map2._mapPane, map2._container);
              this._draggable.on({
                dragstart: this._onDragStart,
                drag: this._onDrag,
                dragend: this._onDragEnd
              }, this);
              this._draggable.on("predrag", this._onPreDragLimit, this);
              if (map2.options.worldCopyJump) {
                this._draggable.on("predrag", this._onPreDragWrap, this);
                map2.on("zoomend", this._onZoomEnd, this);
                map2.whenReady(this._onZoomEnd, this);
              }
            }
            addClass(this._map._container, "leaflet-grab leaflet-touch-drag");
            this._draggable.enable();
            this._positions = [];
            this._times = [];
          },
          removeHooks: function() {
            removeClass(this._map._container, "leaflet-grab");
            removeClass(this._map._container, "leaflet-touch-drag");
            this._draggable.disable();
          },
          moved: function() {
            return this._draggable && this._draggable._moved;
          },
          moving: function() {
            return this._draggable && this._draggable._moving;
          },
          _onDragStart: function() {
            var map2 = this._map;
            map2._stop();
            if (this._map.options.maxBounds && this._map.options.maxBoundsViscosity) {
              var bounds = toLatLngBounds(this._map.options.maxBounds);
              this._offsetLimit = toBounds(
                this._map.latLngToContainerPoint(bounds.getNorthWest()).multiplyBy(-1),
                this._map.latLngToContainerPoint(bounds.getSouthEast()).multiplyBy(-1).add(this._map.getSize())
              );
              this._viscosity = Math.min(1, Math.max(0, this._map.options.maxBoundsViscosity));
            } else {
              this._offsetLimit = null;
            }
            map2.fire("movestart").fire("dragstart");
            if (map2.options.inertia) {
              this._positions = [];
              this._times = [];
            }
          },
          _onDrag: function(e) {
            if (this._map.options.inertia) {
              var time = this._lastTime = +/* @__PURE__ */ new Date(), pos = this._lastPos = this._draggable._absPos || this._draggable._newPos;
              this._positions.push(pos);
              this._times.push(time);
              this._prunePositions(time);
            }
            this._map.fire("move", e).fire("drag", e);
          },
          _prunePositions: function(time) {
            while (this._positions.length > 1 && time - this._times[0] > 50) {
              this._positions.shift();
              this._times.shift();
            }
          },
          _onZoomEnd: function() {
            var pxCenter = this._map.getSize().divideBy(2), pxWorldCenter = this._map.latLngToLayerPoint([0, 0]);
            this._initialWorldOffset = pxWorldCenter.subtract(pxCenter).x;
            this._worldWidth = this._map.getPixelWorldBounds().getSize().x;
          },
          _viscousLimit: function(value, threshold) {
            return value - (value - threshold) * this._viscosity;
          },
          _onPreDragLimit: function() {
            if (!this._viscosity || !this._offsetLimit) {
              return;
            }
            var offset = this._draggable._newPos.subtract(this._draggable._startPos);
            var limit = this._offsetLimit;
            if (offset.x < limit.min.x) {
              offset.x = this._viscousLimit(offset.x, limit.min.x);
            }
            if (offset.y < limit.min.y) {
              offset.y = this._viscousLimit(offset.y, limit.min.y);
            }
            if (offset.x > limit.max.x) {
              offset.x = this._viscousLimit(offset.x, limit.max.x);
            }
            if (offset.y > limit.max.y) {
              offset.y = this._viscousLimit(offset.y, limit.max.y);
            }
            this._draggable._newPos = this._draggable._startPos.add(offset);
          },
          _onPreDragWrap: function() {
            var worldWidth = this._worldWidth, halfWidth = Math.round(worldWidth / 2), dx = this._initialWorldOffset, x = this._draggable._newPos.x, newX1 = (x - halfWidth + dx) % worldWidth + halfWidth - dx, newX2 = (x + halfWidth + dx) % worldWidth - halfWidth - dx, newX = Math.abs(newX1 + dx) < Math.abs(newX2 + dx) ? newX1 : newX2;
            this._draggable._absPos = this._draggable._newPos.clone();
            this._draggable._newPos.x = newX;
          },
          _onDragEnd: function(e) {
            var map2 = this._map, options = map2.options, noInertia = !options.inertia || e.noInertia || this._times.length < 2;
            map2.fire("dragend", e);
            if (noInertia) {
              map2.fire("moveend");
            } else {
              this._prunePositions(+/* @__PURE__ */ new Date());
              var direction = this._lastPos.subtract(this._positions[0]), duration = (this._lastTime - this._times[0]) / 1e3, ease = options.easeLinearity, speedVector = direction.multiplyBy(ease / duration), speed = speedVector.distanceTo([0, 0]), limitedSpeed = Math.min(options.inertiaMaxSpeed, speed), limitedSpeedVector = speedVector.multiplyBy(limitedSpeed / speed), decelerationDuration = limitedSpeed / (options.inertiaDeceleration * ease), offset = limitedSpeedVector.multiplyBy(-decelerationDuration / 2).round();
              if (!offset.x && !offset.y) {
                map2.fire("moveend");
              } else {
                offset = map2._limitOffset(offset, map2.options.maxBounds);
                requestAnimFrame(function() {
                  map2.panBy(offset, {
                    duration: decelerationDuration,
                    easeLinearity: ease,
                    noMoveStart: true,
                    animate: true
                  });
                });
              }
            }
          }
        });
        Map2.addInitHook("addHandler", "dragging", Drag);
        Map2.mergeOptions({
          // @option keyboard: Boolean = true
          // Makes the map focusable and allows users to navigate the map with keyboard
          // arrows and `+`/`-` keys.
          keyboard: true,
          // @option keyboardPanDelta: Number = 80
          // Amount of pixels to pan when pressing an arrow key.
          keyboardPanDelta: 80
        });
        var Keyboard = Handler.extend({
          keyCodes: {
            left: [37],
            right: [39],
            down: [40],
            up: [38],
            zoomIn: [187, 107, 61, 171],
            zoomOut: [189, 109, 54, 173]
          },
          initialize: function(map2) {
            this._map = map2;
            this._setPanDelta(map2.options.keyboardPanDelta);
            this._setZoomDelta(map2.options.zoomDelta);
          },
          addHooks: function() {
            var container = this._map._container;
            if (container.tabIndex <= 0) {
              container.tabIndex = "0";
            }
            on(container, {
              focus: this._onFocus,
              blur: this._onBlur,
              mousedown: this._onMouseDown
            }, this);
            this._map.on({
              focus: this._addHooks,
              blur: this._removeHooks
            }, this);
          },
          removeHooks: function() {
            this._removeHooks();
            off(this._map._container, {
              focus: this._onFocus,
              blur: this._onBlur,
              mousedown: this._onMouseDown
            }, this);
            this._map.off({
              focus: this._addHooks,
              blur: this._removeHooks
            }, this);
          },
          _onMouseDown: function() {
            if (this._focused) {
              return;
            }
            var body = document.body, docEl = document.documentElement, top = body.scrollTop || docEl.scrollTop, left = body.scrollLeft || docEl.scrollLeft;
            this._map._container.focus();
            window.scrollTo(left, top);
          },
          _onFocus: function() {
            this._focused = true;
            this._map.fire("focus");
          },
          _onBlur: function() {
            this._focused = false;
            this._map.fire("blur");
          },
          _setPanDelta: function(panDelta) {
            var keys = this._panKeys = {}, codes = this.keyCodes, i, len;
            for (i = 0, len = codes.left.length; i < len; i++) {
              keys[codes.left[i]] = [-1 * panDelta, 0];
            }
            for (i = 0, len = codes.right.length; i < len; i++) {
              keys[codes.right[i]] = [panDelta, 0];
            }
            for (i = 0, len = codes.down.length; i < len; i++) {
              keys[codes.down[i]] = [0, panDelta];
            }
            for (i = 0, len = codes.up.length; i < len; i++) {
              keys[codes.up[i]] = [0, -1 * panDelta];
            }
          },
          _setZoomDelta: function(zoomDelta) {
            var keys = this._zoomKeys = {}, codes = this.keyCodes, i, len;
            for (i = 0, len = codes.zoomIn.length; i < len; i++) {
              keys[codes.zoomIn[i]] = zoomDelta;
            }
            for (i = 0, len = codes.zoomOut.length; i < len; i++) {
              keys[codes.zoomOut[i]] = -zoomDelta;
            }
          },
          _addHooks: function() {
            on(document, "keydown", this._onKeyDown, this);
          },
          _removeHooks: function() {
            off(document, "keydown", this._onKeyDown, this);
          },
          _onKeyDown: function(e) {
            if (e.altKey || e.ctrlKey || e.metaKey) {
              return;
            }
            var key = e.keyCode, map2 = this._map, offset;
            if (key in this._panKeys) {
              if (!map2._panAnim || !map2._panAnim._inProgress) {
                offset = this._panKeys[key];
                if (e.shiftKey) {
                  offset = toPoint(offset).multiplyBy(3);
                }
                if (map2.options.maxBounds) {
                  offset = map2._limitOffset(toPoint(offset), map2.options.maxBounds);
                }
                if (map2.options.worldCopyJump) {
                  var newLatLng = map2.wrapLatLng(map2.unproject(map2.project(map2.getCenter()).add(offset)));
                  map2.panTo(newLatLng);
                } else {
                  map2.panBy(offset);
                }
              }
            } else if (key in this._zoomKeys) {
              map2.setZoom(map2.getZoom() + (e.shiftKey ? 3 : 1) * this._zoomKeys[key]);
            } else if (key === 27 && map2._popup && map2._popup.options.closeOnEscapeKey) {
              map2.closePopup();
            } else {
              return;
            }
            stop(e);
          }
        });
        Map2.addInitHook("addHandler", "keyboard", Keyboard);
        Map2.mergeOptions({
          // @section Mouse wheel options
          // @option scrollWheelZoom: Boolean|String = true
          // Whether the map can be zoomed by using the mouse wheel. If passed `'center'`,
          // it will zoom to the center of the view regardless of where the mouse was.
          scrollWheelZoom: true,
          // @option wheelDebounceTime: Number = 40
          // Limits the rate at which a wheel can fire (in milliseconds). By default
          // user can't zoom via wheel more often than once per 40 ms.
          wheelDebounceTime: 40,
          // @option wheelPxPerZoomLevel: Number = 60
          // How many scroll pixels (as reported by [L.DomEvent.getWheelDelta](#domevent-getwheeldelta))
          // mean a change of one full zoom level. Smaller values will make wheel-zooming
          // faster (and vice versa).
          wheelPxPerZoomLevel: 60
        });
        var ScrollWheelZoom = Handler.extend({
          addHooks: function() {
            on(this._map._container, "wheel", this._onWheelScroll, this);
            this._delta = 0;
          },
          removeHooks: function() {
            off(this._map._container, "wheel", this._onWheelScroll, this);
          },
          _onWheelScroll: function(e) {
            var delta = getWheelDelta(e);
            var debounce = this._map.options.wheelDebounceTime;
            this._delta += delta;
            this._lastMousePos = this._map.mouseEventToContainerPoint(e);
            if (!this._startTime) {
              this._startTime = +/* @__PURE__ */ new Date();
            }
            var left = Math.max(debounce - (+/* @__PURE__ */ new Date() - this._startTime), 0);
            clearTimeout(this._timer);
            this._timer = setTimeout(bind(this._performZoom, this), left);
            stop(e);
          },
          _performZoom: function() {
            var map2 = this._map, zoom2 = map2.getZoom(), snap = this._map.options.zoomSnap || 0;
            map2._stop();
            var d2 = this._delta / (this._map.options.wheelPxPerZoomLevel * 4), d3 = 4 * Math.log(2 / (1 + Math.exp(-Math.abs(d2)))) / Math.LN2, d4 = snap ? Math.ceil(d3 / snap) * snap : d3, delta = map2._limitZoom(zoom2 + (this._delta > 0 ? d4 : -d4)) - zoom2;
            this._delta = 0;
            this._startTime = null;
            if (!delta) {
              return;
            }
            if (map2.options.scrollWheelZoom === "center") {
              map2.setZoom(zoom2 + delta);
            } else {
              map2.setZoomAround(this._lastMousePos, zoom2 + delta);
            }
          }
        });
        Map2.addInitHook("addHandler", "scrollWheelZoom", ScrollWheelZoom);
        var tapHoldDelay = 600;
        Map2.mergeOptions({
          // @section Touch interaction options
          // @option tapHold: Boolean
          // Enables simulation of `contextmenu` event, default is `true` for mobile Safari.
          tapHold: Browser.touchNative && Browser.safari && Browser.mobile,
          // @option tapTolerance: Number = 15
          // The max number of pixels a user can shift his finger during touch
          // for it to be considered a valid tap.
          tapTolerance: 15
        });
        var TapHold = Handler.extend({
          addHooks: function() {
            on(this._map._container, "touchstart", this._onDown, this);
          },
          removeHooks: function() {
            off(this._map._container, "touchstart", this._onDown, this);
          },
          _onDown: function(e) {
            clearTimeout(this._holdTimeout);
            if (e.touches.length !== 1) {
              return;
            }
            var first = e.touches[0];
            this._startPos = this._newPos = new Point(first.clientX, first.clientY);
            this._holdTimeout = setTimeout(bind(function() {
              this._cancel();
              if (!this._isTapValid()) {
                return;
              }
              on(document, "touchend", preventDefault);
              on(document, "touchend touchcancel", this._cancelClickPrevent);
              this._simulateEvent("contextmenu", first);
            }, this), tapHoldDelay);
            on(document, "touchend touchcancel contextmenu", this._cancel, this);
            on(document, "touchmove", this._onMove, this);
          },
          _cancelClickPrevent: function cancelClickPrevent() {
            off(document, "touchend", preventDefault);
            off(document, "touchend touchcancel", cancelClickPrevent);
          },
          _cancel: function() {
            clearTimeout(this._holdTimeout);
            off(document, "touchend touchcancel contextmenu", this._cancel, this);
            off(document, "touchmove", this._onMove, this);
          },
          _onMove: function(e) {
            var first = e.touches[0];
            this._newPos = new Point(first.clientX, first.clientY);
          },
          _isTapValid: function() {
            return this._newPos.distanceTo(this._startPos) <= this._map.options.tapTolerance;
          },
          _simulateEvent: function(type, e) {
            var simulatedEvent = new MouseEvent(type, {
              bubbles: true,
              cancelable: true,
              view: window,
              // detail: 1,
              screenX: e.screenX,
              screenY: e.screenY,
              clientX: e.clientX,
              clientY: e.clientY
              // button: 2,
              // buttons: 2
            });
            simulatedEvent._simulated = true;
            e.target.dispatchEvent(simulatedEvent);
          }
        });
        Map2.addInitHook("addHandler", "tapHold", TapHold);
        Map2.mergeOptions({
          // @section Touch interaction options
          // @option touchZoom: Boolean|String = *
          // Whether the map can be zoomed by touch-dragging with two fingers. If
          // passed `'center'`, it will zoom to the center of the view regardless of
          // where the touch events (fingers) were. Enabled for touch-capable web
          // browsers.
          touchZoom: Browser.touch,
          // @option bounceAtZoomLimits: Boolean = true
          // Set it to false if you don't want the map to zoom beyond min/max zoom
          // and then bounce back when pinch-zooming.
          bounceAtZoomLimits: true
        });
        var TouchZoom = Handler.extend({
          addHooks: function() {
            addClass(this._map._container, "leaflet-touch-zoom");
            on(this._map._container, "touchstart", this._onTouchStart, this);
          },
          removeHooks: function() {
            removeClass(this._map._container, "leaflet-touch-zoom");
            off(this._map._container, "touchstart", this._onTouchStart, this);
          },
          _onTouchStart: function(e) {
            var map2 = this._map;
            if (!e.touches || e.touches.length !== 2 || map2._animatingZoom || this._zooming) {
              return;
            }
            var p1 = map2.mouseEventToContainerPoint(e.touches[0]), p2 = map2.mouseEventToContainerPoint(e.touches[1]);
            this._centerPoint = map2.getSize()._divideBy(2);
            this._startLatLng = map2.containerPointToLatLng(this._centerPoint);
            if (map2.options.touchZoom !== "center") {
              this._pinchStartLatLng = map2.containerPointToLatLng(p1.add(p2)._divideBy(2));
            }
            this._startDist = p1.distanceTo(p2);
            this._startZoom = map2.getZoom();
            this._moved = false;
            this._zooming = true;
            map2._stop();
            on(document, "touchmove", this._onTouchMove, this);
            on(document, "touchend touchcancel", this._onTouchEnd, this);
            preventDefault(e);
          },
          _onTouchMove: function(e) {
            if (!e.touches || e.touches.length !== 2 || !this._zooming) {
              return;
            }
            var map2 = this._map, p1 = map2.mouseEventToContainerPoint(e.touches[0]), p2 = map2.mouseEventToContainerPoint(e.touches[1]), scale2 = p1.distanceTo(p2) / this._startDist;
            this._zoom = map2.getScaleZoom(scale2, this._startZoom);
            if (!map2.options.bounceAtZoomLimits && (this._zoom < map2.getMinZoom() && scale2 < 1 || this._zoom > map2.getMaxZoom() && scale2 > 1)) {
              this._zoom = map2._limitZoom(this._zoom);
            }
            if (map2.options.touchZoom === "center") {
              this._center = this._startLatLng;
              if (scale2 === 1) {
                return;
              }
            } else {
              var delta = p1._add(p2)._divideBy(2)._subtract(this._centerPoint);
              if (scale2 === 1 && delta.x === 0 && delta.y === 0) {
                return;
              }
              this._center = map2.unproject(map2.project(this._pinchStartLatLng, this._zoom).subtract(delta), this._zoom);
            }
            if (!this._moved) {
              map2._moveStart(true, false);
              this._moved = true;
            }
            cancelAnimFrame(this._animRequest);
            var moveFn = bind(map2._move, map2, this._center, this._zoom, { pinch: true, round: false }, void 0);
            this._animRequest = requestAnimFrame(moveFn, this, true);
            preventDefault(e);
          },
          _onTouchEnd: function() {
            if (!this._moved || !this._zooming) {
              this._zooming = false;
              return;
            }
            this._zooming = false;
            cancelAnimFrame(this._animRequest);
            off(document, "touchmove", this._onTouchMove, this);
            off(document, "touchend touchcancel", this._onTouchEnd, this);
            if (this._map.options.zoomAnimation) {
              this._map._animateZoom(this._center, this._map._limitZoom(this._zoom), true, this._map.options.zoomSnap);
            } else {
              this._map._resetView(this._center, this._map._limitZoom(this._zoom));
            }
          }
        });
        Map2.addInitHook("addHandler", "touchZoom", TouchZoom);
        Map2.BoxZoom = BoxZoom;
        Map2.DoubleClickZoom = DoubleClickZoom;
        Map2.Drag = Drag;
        Map2.Keyboard = Keyboard;
        Map2.ScrollWheelZoom = ScrollWheelZoom;
        Map2.TapHold = TapHold;
        Map2.TouchZoom = TouchZoom;
        exports2.Bounds = Bounds;
        exports2.Browser = Browser;
        exports2.CRS = CRS;
        exports2.Canvas = Canvas;
        exports2.Circle = Circle;
        exports2.CircleMarker = CircleMarker;
        exports2.Class = Class;
        exports2.Control = Control;
        exports2.DivIcon = DivIcon;
        exports2.DivOverlay = DivOverlay;
        exports2.DomEvent = DomEvent;
        exports2.DomUtil = DomUtil;
        exports2.Draggable = Draggable;
        exports2.Evented = Evented;
        exports2.FeatureGroup = FeatureGroup;
        exports2.GeoJSON = GeoJSON;
        exports2.GridLayer = GridLayer;
        exports2.Handler = Handler;
        exports2.Icon = Icon;
        exports2.ImageOverlay = ImageOverlay;
        exports2.LatLng = LatLng;
        exports2.LatLngBounds = LatLngBounds;
        exports2.Layer = Layer;
        exports2.LayerGroup = LayerGroup;
        exports2.LineUtil = LineUtil;
        exports2.Map = Map2;
        exports2.Marker = Marker;
        exports2.Mixin = Mixin;
        exports2.Path = Path;
        exports2.Point = Point;
        exports2.PolyUtil = PolyUtil;
        exports2.Polygon = Polygon;
        exports2.Polyline = Polyline;
        exports2.Popup = Popup;
        exports2.PosAnimation = PosAnimation;
        exports2.Projection = index;
        exports2.Rectangle = Rectangle;
        exports2.Renderer = Renderer;
        exports2.SVG = SVG;
        exports2.SVGOverlay = SVGOverlay;
        exports2.TileLayer = TileLayer;
        exports2.Tooltip = Tooltip;
        exports2.Transformation = Transformation;
        exports2.Util = Util;
        exports2.VideoOverlay = VideoOverlay;
        exports2.bind = bind;
        exports2.bounds = toBounds;
        exports2.canvas = canvas;
        exports2.circle = circle;
        exports2.circleMarker = circleMarker2;
        exports2.control = control;
        exports2.divIcon = divIcon;
        exports2.extend = extend;
        exports2.featureGroup = featureGroup;
        exports2.geoJSON = geoJSON;
        exports2.geoJson = geoJson;
        exports2.gridLayer = gridLayer;
        exports2.icon = icon;
        exports2.imageOverlay = imageOverlay;
        exports2.latLng = toLatLng;
        exports2.latLngBounds = toLatLngBounds;
        exports2.layerGroup = layerGroup;
        exports2.map = createMap;
        exports2.marker = marker;
        exports2.point = toPoint;
        exports2.polygon = polygon;
        exports2.polyline = polyline2;
        exports2.popup = popup;
        exports2.rectangle = rectangle;
        exports2.setOptions = setOptions;
        exports2.stamp = stamp;
        exports2.svg = svg;
        exports2.svgOverlay = svgOverlay;
        exports2.tileLayer = tileLayer2;
        exports2.tooltip = tooltip;
        exports2.transformation = toTransformation;
        exports2.version = version;
        exports2.videoOverlay = videoOverlay;
        var oldL = window.L;
        exports2.noConflict = function() {
          window.L = oldL;
          return this;
        };
        window.L = exports2;
      }));
    }
  });

  // ../../obsidian-plugin-hub/obsidian-health-md/src/canvas-utils.ts
  var COLOR_SCHEMES = {
    default: {
      label: "Default",
      accent: "#2dd4bf",
      secondary: "#f59e0b",
      heart: "#ef4444",
      sleepDeep: "#312e81",
      sleepRem: "#7c3aed",
      sleepCore: "#2dd4bf",
      sleepAwake: "#f59e0b"
    },
    ocean: {
      label: "Ocean",
      accent: "#0ea5e9",
      secondary: "#38bdf8",
      heart: "#e11d48",
      sleepDeep: "#0c2461",
      sleepRem: "#1d4ed8",
      sleepCore: "#0ea5e9",
      sleepAwake: "#7dd3fc"
    },
    forest: {
      label: "Forest",
      accent: "#22c55e",
      secondary: "#84cc16",
      heart: "#ef4444",
      sleepDeep: "#14532d",
      sleepRem: "#15803d",
      sleepCore: "#4ade80",
      sleepAwake: "#bbf7d0"
    },
    sunset: {
      label: "Sunset",
      accent: "#f97316",
      secondary: "#ec4899",
      heart: "#ef4444",
      sleepDeep: "#7f1d1d",
      sleepRem: "#be185d",
      sleepCore: "#f97316",
      sleepAwake: "#fbbf24"
    },
    aurora: {
      label: "Aurora",
      accent: "#a855f7",
      secondary: "#06b6d4",
      heart: "#f43f5e",
      sleepDeep: "#1e1b4b",
      sleepRem: "#6d28d9",
      sleepCore: "#a855f7",
      sleepAwake: "#818cf8"
    },
    monochrome: {
      label: "Monochrome",
      accent: "#94a3b8",
      secondary: "#64748b",
      heart: "#475569",
      sleepDeep: "#0f172a",
      sleepRem: "#334155",
      sleepCore: "#64748b",
      sleepAwake: "#cbd5e1"
    }
  };
  function lerp(a, b, t) {
    return a + (b - a) * t;
  }
  function formatDate(iso) {
    const d = /* @__PURE__ */ new Date(iso + "T00:00:00");
    return d.toLocaleDateString("en-US", {
      weekday: "short",
      month: "short",
      day: "numeric",
      year: "numeric"
    });
  }
  function formatDuration(seconds) {
    const h = Math.floor(seconds / 3600);
    const m = Math.round(seconds % 3600 / 60);
    if (h === 0) return `${m}m`;
    return `${h}h ${m}m`;
  }
  function hsl(h, s, l) {
    return `hsl(${h},${s}%,${l}%)`;
  }
  function hexToRgba(hex, alpha) {
    const normalized = normalizeColor(hex, "#000000");
    const r = parseInt(normalized.slice(1, 3), 16);
    const g = parseInt(normalized.slice(3, 5), 16);
    const b = parseInt(normalized.slice(5, 7), 16);
    return `rgba(${r},${g},${b},${alpha})`;
  }
  function hexToRgb(hex) {
    const normalized = normalizeColor(hex, "#000000");
    return {
      r: parseInt(normalized.slice(1, 3), 16),
      g: parseInt(normalized.slice(3, 5), 16),
      b: parseInt(normalized.slice(5, 7), 16)
    };
  }
  function normalizeHexColor(value) {
    const trimmed = value.trim();
    const short = /^#([0-9a-f]{3})$/i.exec(trimmed);
    if (short) {
      return `#${short[1].split("").map((c) => c + c).join("")}`.toLowerCase();
    }
    if (/^#[0-9a-f]{6}$/i.test(trimmed)) return trimmed.toLowerCase();
    return null;
  }
  function rgbToHex(r, g, b) {
    return `#${[r, g, b].map((n) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, "0")).join("")}`;
  }
  function parseRgbColor(value) {
    const match = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*[\d.]+)?\s*\)$/i.exec(value.trim());
    if (!match) return null;
    return rgbToHex(Number(match[1]), Number(match[2]), Number(match[3]));
  }
  function cssColorToHex(value) {
    var _a;
    const trimmed = value.trim();
    if (!trimmed) return null;
    const hex = normalizeHexColor(trimmed);
    if (hex) return hex;
    const rgb = parseRgbColor(trimmed);
    if (rgb) return rgb;
    try {
      const probe = activeDocument.createElement("span");
      probe.style.color = trimmed;
      if (!probe.style.color && !trimmed.startsWith("var(")) return null;
      activeDocument.body.appendChild(probe);
      const computed = activeWindow.getComputedStyle(probe).color;
      probe.remove();
      return (_a = parseRgbColor(computed)) != null ? _a : normalizeHexColor(computed);
    } catch (e) {
      return null;
    }
  }
  function normalizeColor(value, fallback) {
    var _a;
    if (typeof value !== "string") return fallback;
    return (_a = cssColorToHex(value)) != null ? _a : fallback;
  }
  function getCssColor(name, fallback) {
    try {
      const value = activeWindow.getComputedStyle(activeDocument.body).getPropertyValue(name);
      return normalizeColor(value, fallback);
    } catch (e) {
      return fallback;
    }
  }
  function configColor(config, keys, fallback) {
    if (!config) return fallback;
    for (const key of keys) {
      const value = config[key];
      if (typeof value === "string") {
        const color = normalizeColor(value, "");
        if (color) return color;
      }
    }
    return fallback;
  }
  function normalizeThemeMode(value, fallback) {
    if (typeof value !== "string") return fallback;
    const mode = value.trim().toLowerCase();
    return mode === "auto" || mode === "dark" || mode === "light" ? mode : fallback;
  }
  function normalizeColorScheme(value) {
    if (typeof value !== "string") return null;
    const scheme = value.trim().toLowerCase();
    if (scheme === "theme" || scheme === "custom") return scheme;
    if (Object.prototype.hasOwnProperty.call(COLOR_SCHEMES, scheme)) {
      return scheme;
    }
    return null;
  }
  function resolveTheme(settings, config) {
    var _a;
    const themeMode = normalizeThemeMode(config == null ? void 0 : config.theme, settings.theme);
    let isDark;
    if (themeMode === "auto") {
      isDark = activeDocument.body.classList.contains("theme-dark");
    } else {
      isDark = themeMode === "dark";
    }
    const fallbackBase = isDark ? { bg: "#0a0a0f", fg: "#e0e0e0", muted: "#555555", isDark: true } : { bg: "#ffffff", fg: "#1a1a1a", muted: "#999999", isDark: false };
    const obsidianBase = themeMode === "auto" ? {
      bg: getCssColor("--background-primary", fallbackBase.bg),
      fg: getCssColor("--text-normal", fallbackBase.fg),
      muted: getCssColor("--text-muted", fallbackBase.muted),
      isDark
    } : fallbackBase;
    const requestedScheme = normalizeColorScheme((_a = config == null ? void 0 : config.colorScheme) != null ? _a : config == null ? void 0 : config.palette);
    const scheme = requestedScheme != null ? requestedScheme : settings.colorScheme;
    const preset = scheme !== "custom" && scheme !== "theme" ? COLOR_SCHEMES[scheme] : void 0;
    const themeAccent = getCssColor("--interactive-accent", getCssColor("--color-accent", settings.colorAccent));
    const themeSecondary = getCssColor("--text-accent", getCssColor("--interactive-accent-hover", settings.colorSecondary));
    const palette = preset ? {
      accent: preset.accent,
      secondary: preset.secondary,
      heart: preset.heart,
      sleepDeep: preset.sleepDeep,
      sleepRem: preset.sleepRem,
      sleepCore: preset.sleepCore,
      sleepAwake: preset.sleepAwake
    } : scheme === "theme" ? {
      accent: themeAccent,
      secondary: themeSecondary,
      heart: settings.colorHeart,
      sleepDeep: settings.colorSleepDeep,
      sleepRem: settings.colorSleepRem,
      sleepCore: themeAccent,
      sleepAwake: settings.colorSleepAwake
    } : {
      accent: settings.colorAccent,
      secondary: settings.colorSecondary,
      heart: settings.colorHeart,
      sleepDeep: settings.colorSleepDeep,
      sleepRem: settings.colorSleepRem,
      sleepCore: settings.colorSleepCore,
      sleepAwake: settings.colorSleepAwake
    };
    return {
      bg: configColor(config, ["background", "bg", "colorBackground"], obsidianBase.bg),
      fg: configColor(config, ["foreground", "fg", "text", "colorForeground"], obsidianBase.fg),
      muted: configColor(config, ["muted", "textMuted", "colorMuted"], obsidianBase.muted),
      isDark,
      colors: {
        accent: configColor(config, ["accent", "colorAccent"], palette.accent),
        secondary: configColor(config, ["secondary", "colorSecondary"], palette.secondary),
        heart: configColor(config, ["heart", "heartRate", "colorHeart"], palette.heart),
        sleep: {
          deep: configColor(config, ["sleepDeep", "colorSleepDeep"], palette.sleepDeep),
          rem: configColor(config, ["sleepRem", "colorSleepRem"], palette.sleepRem),
          core: configColor(config, ["sleepCore", "colorSleepCore"], palette.sleepCore),
          awake: configColor(config, ["sleepAwake", "colorSleepAwake"], palette.sleepAwake)
        },
        activity: {
          move: configColor(config, ["activityMove", "move", "colorActivityMove"], palette.heart),
          exercise: configColor(config, ["activityExercise", "exercise", "colorActivityExercise"], palette.accent),
          stand: configColor(config, ["activityStand", "stand", "colorActivityStand"], palette.secondary)
        }
      },
      maxHeartRate: settings.maxHeartRate,
      mapTilesEnabled: settings.mapTilesEnabled,
      mapTileUrl: settings.mapTileUrl,
      mapTileAttribution: settings.mapTileAttribution
    };
  }

  // ../../obsidian-plugin-hub/obsidian-health-md/src/dom-utils.ts
  function renderStatBoxes(statsEl, boxes) {
    statsEl.empty();
    boxes.forEach(({ value, label, color }) => {
      const box = statsEl.createDiv({ cls: "health-md-stat-box" });
      const valueEl = box.createDiv({
        cls: "health-md-stat-value",
        text: value
      });
      if (color) {
        valueEl.style.color = color;
      }
      box.createDiv({ cls: "health-md-stat-label", text: label });
    });
  }
  function renderInlineStats(statsEl, stats) {
    statsEl.empty();
    stats.forEach((parts) => {
      const row = statsEl.createSpan();
      parts.forEach((part) => {
        if (part.strong) {
          row.createEl("strong", { text: part.text });
          return;
        }
        row.appendChild(activeDocument.createTextNode(part.text));
      });
    });
  }
  function appendSvgFromMarkup(container, svgMarkup) {
    const parser = new DOMParser();
    const doc = parser.parseFromString(svgMarkup, "image/svg+xml");
    const svg = doc.documentElement;
    if (svg.tagName.toLowerCase() !== "svg") return;
    container.appendChild(activeDocument.importNode(svg, true));
  }

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/heart-terrain.ts
  var renderHeartTerrain = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    const BUCKETS = 96;
    const days = data.filter((d) => {
      var _a, _b;
      return (_b = (_a = d.heart) == null ? void 0 : _a.heartRateSamples) == null ? void 0 : _b.length;
    });
    const grid = [];
    let minBPM = 999, maxBPM = 0;
    days.forEach((day) => {
      const col = new Array(BUCKETS).fill(null);
      day.heart.heartRateSamples.forEach((s) => {
        const dt = new Date(s.timestamp);
        const mins = dt.getHours() * 60 + dt.getMinutes();
        const bucket = Math.floor(mins / 15);
        if (bucket >= 0 && bucket < BUCKETS) {
          if (!col[bucket]) col[bucket] = [];
          const bucketValues = col[bucket];
          if (bucketValues) {
            bucketValues.push(s.value);
          }
        }
      });
      const averaged = col.map(
        (bucketValues) => bucketValues ? bucketValues.reduce((sum, value) => sum + value, 0) / bucketValues.length : null
      );
      averaged.forEach((v) => {
        if (v) {
          minBPM = Math.min(minBPM, v);
          maxBPM = Math.max(maxBPM, v);
        }
      });
      grid.push({ date: day.date, col: averaged });
    });
    if (grid.length === 0) {
      const heartDays = data.filter((d) => d.heart && d.heart.averageHeartRate > 0);
      if (!heartDays.length) {
        statsEl.empty();
        statsEl.createEl("p", {
          text: "No heart rate data available.",
          cls: "health-md-muted"
        });
        return;
      }
      const allAvg = heartDays.map((d) => d.heart.averageHeartRate);
      const globalMin = Math.min(
        ...heartDays.map((d) => d.heart.heartRateMin || d.heart.averageHeartRate)
      );
      const globalMax = Math.max(
        ...heartDays.map((d) => d.heart.heartRateMax || d.heart.averageHeartRate)
      );
      const colW2 = W / heartDays.length;
      heartDays.forEach((day, x) => {
        const avg3 = day.heart.averageHeartRate;
        const lo = day.heart.heartRateMin || avg3;
        const hi = day.heart.heartRateMax || avg3;
        const grad = ctx.createLinearGradient(0, H, 0, 0);
        const tLo = (lo - globalMin) / (globalMax - globalMin || 1);
        const tHi = (hi - globalMin) / (globalMax - globalMin || 1);
        const tAvg = (avg3 - globalMin) / (globalMax - globalMin || 1);
        grad.addColorStop(
          0,
          `hsl(${lerp(220, 0, tLo)},70%,${theme.isDark ? 30 : 45}%)`
        );
        grad.addColorStop(
          0.5,
          `hsl(${lerp(220, 0, tAvg)},80%,${theme.isDark ? 45 : 55}%)`
        );
        grad.addColorStop(
          1,
          `hsl(${lerp(220, 0, tHi)},90%,${theme.isDark ? 55 : 65}%)`
        );
        ctx.fillStyle = grad;
        ctx.fillRect(x * colW2, 0, colW2 + 1, H);
        hits.add({
          shape: "rect",
          x: x * colW2,
          y: 0,
          w: colW2,
          h: H,
          title: formatDate(day.date),
          details: [
            { label: "Avg", value: `${Math.round(avg3)} bpm` },
            { label: "Min", value: `${lo} bpm` },
            { label: "Max", value: `${hi} bpm` }
          ],
          payload: day
        });
      });
      const overallAvg = Math.round(
        allAvg.reduce((a, b) => a + b, 0) / allAvg.length
      );
      renderStatBoxes(statsEl, [
        { value: String(globalMin), label: "Lowest", color: "#4488ff" },
        { value: String(overallAvg), label: "Average", color: "#cc6666" },
        { value: String(globalMax), label: "Highest", color: "#ff4444" }
      ]);
      return;
    }
    const colW = W / grid.length;
    const rowH = H / BUCKETS;
    grid.forEach((day, x) => {
      day.col.forEach((bpm, y) => {
        if (bpm === null) return;
        const t = (bpm - minBPM) / (maxBPM - minBPM);
        const h = lerp(220, 0, t);
        const s = lerp(60, 100, t);
        const l = lerp(theme.isDark ? 12 : 30, theme.isDark ? 55 : 65, t);
        ctx.fillStyle = hsl(h, s, l);
        ctx.fillRect(x * colW, y * rowH, colW + 1, rowH + 1);
      });
      const dayObj = days[x];
      const samples = dayObj.heart.heartRateSamples;
      hits.add({
        shape: "rect",
        x: x * colW,
        y: 0,
        w: colW,
        h: H,
        title: formatDate(day.date),
        details: [
          { label: "Avg", value: `${Math.round(dayObj.heart.averageHeartRate)} bpm` },
          { label: "Min", value: `${dayObj.heart.heartRateMin} bpm` },
          { label: "Max", value: `${dayObj.heart.heartRateMax} bpm` },
          { label: "Samples", value: `${samples.length}` }
        ],
        payload: dayObj
      });
    });
    const minHR = Math.min(...days.map((d) => d.heart.heartRateMin || 999));
    const maxHR = Math.max(...days.map((d) => d.heart.heartRateMax || 0));
    const avgHR = Math.round(
      days.reduce((s, d) => s + (d.heart.averageHeartRate || 0), 0) / days.length
    );
    renderStatBoxes(statsEl, [
      { value: String(minHR), label: "Lowest", color: "#4488ff" },
      { value: String(avgHR), label: "Average", color: "#cc6666" },
      { value: String(maxHR), label: "Highest", color: "#ff4444" }
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/sleep-polar.ts
  function buildSyntheticStages(night) {
    var _a, _b, _c, _d;
    const sleep = night.sleep;
    if (!sleep.bedtime || !sleep.wakeTime) return [];
    const isTimeOnly = (s) => /^\d{1,2}:\d{2}$/.test(s);
    let bedMs;
    let wakeMs;
    if (isTimeOnly(sleep.bedtime)) {
      bedMs = (/* @__PURE__ */ new Date(`${night.date}T${sleep.bedtime}:00`)).getTime();
      wakeMs = (/* @__PURE__ */ new Date(`${night.date}T${sleep.wakeTime}:00`)).getTime();
      if (wakeMs <= bedMs) wakeMs += 864e5;
    } else {
      bedMs = Date.parse(sleep.bedtime);
      wakeMs = Date.parse(sleep.wakeTime);
    }
    if (!isFinite(bedMs) || !isFinite(wakeMs) || wakeMs <= bedMs) return [];
    const stages = [];
    let cursor = bedMs;
    function addStage(stage, secs) {
      if (secs <= 0) return;
      const startDate = new Date(cursor).toISOString();
      cursor += secs * 1e3;
      stages.push({ stage, startDate, endDate: new Date(cursor).toISOString(), durationSeconds: Math.round(secs) });
    }
    const awake = (_a = sleep.awakeTime) != null ? _a : 0;
    const core = (_b = sleep.coreSleep) != null ? _b : 0;
    const deep = (_c = sleep.deepSleep) != null ? _c : 0;
    const rem = (_d = sleep.remSleep) != null ? _d : 0;
    addStage("awake", awake * 0.3);
    addStage("core", core * 0.45);
    addStage("deep", deep);
    addStage("rem", rem);
    addStage("core", core * 0.55);
    addStage("awake", awake * 0.7);
    return stages;
  }
  function getEffectiveStages(night) {
    var _a, _b;
    const stages = (_b = (_a = night.sleep) == null ? void 0 : _a.sleepStages) != null ? _b : [];
    if (stages.length > 0) return stages;
    return buildSyntheticStages(night);
  }
  var renderSleepPolar = (ctx, data, W, H, _config, theme, _statsEl, hits) => {
    const canvas = ctx.canvas;
    const nights = data.filter(
      (d) => d.sleep && (d.sleep.sleepStages.length > 0 || d.sleep.totalDuration > 0)
    );
    if (!nights.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("No sleep data", W / 2, H / 2);
      return;
    }
    const cols = 3;
    const rows = Math.ceil(nights.length / cols);
    const cellW = Math.floor((W - (cols - 1) * 6) / cols);
    const cellH = Math.floor((H - (rows - 1) * 6) / rows);
    const minCellSize = Math.min(42, cellW);
    const cellSize = Math.max(minCellSize, Math.min(cellW, cellH));
    const showDateLabels = cellSize >= 42;
    const labelH = showDateLabels ? 16 : 0;
    const ringSize = cellSize - labelH;
    const actualH = rows * (cellSize + 6) - 6;
    if (actualH !== H) {
      const dpr = activeWindow.devicePixelRatio || 1;
      canvas.width = W * dpr;
      canvas.height = actualH * dpr;
      canvas.style.width = W + "px";
      canvas.style.height = actualH + "px";
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
    }
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, actualH < H ? actualH : H);
    nights.forEach((night, idx) => {
      const row = Math.floor(idx / cols);
      const col = idx % cols;
      const offsetX = col * (cellSize + 6);
      const offsetY = row * (cellSize + 6);
      const cx = offsetX + cellSize / 2;
      const cy = offsetY + ringSize / 2;
      const r = Math.max(4, ringSize / 2 - 8);
      ctx.fillStyle = theme.isDark ? "#0d0d18" : "#f0f0f5";
      ctx.beginPath();
      ctx.arc(cx, cy, r + 6, 0, Math.PI * 2);
      ctx.fill();
      const stages = getEffectiveStages(night);
      if (!stages.length) return;
      const firstStart = new Date(stages[0].startDate).getTime();
      const lastEnd = new Date(stages[stages.length - 1].endDate).getTime();
      const totalSpan = lastEnd - firstStart;
      stages.forEach((stage) => {
        const start = new Date(stage.startDate).getTime();
        const end = new Date(stage.endDate).getTime();
        const a1 = (start - firstStart) / totalSpan * Math.PI * 2 - Math.PI / 2;
        const a2 = (end - firstStart) / totalSpan * Math.PI * 2 - Math.PI / 2;
        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.arc(cx, cy, r - 1, a1, a2);
        ctx.closePath();
        ctx.fillStyle = theme.colors.sleep[stage.stage] || "#333";
        ctx.globalAlpha = 0.85;
        ctx.fill();
        ctx.globalAlpha = 1;
      });
      ctx.fillStyle = theme.bg;
      ctx.beginPath();
      ctx.arc(cx, cy, 5, 0, Math.PI * 2);
      ctx.fill();
      const d = /* @__PURE__ */ new Date(night.date + "T00:00:00");
      if (showDateLabels) {
        ctx.fillStyle = theme.muted;
        ctx.font = `${Math.max(7, Math.min(10, cellSize * 0.09))}px sans-serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(
          d.toLocaleDateString("en-US", { month: "short", day: "numeric" }),
          cx,
          offsetY + ringSize + labelH / 2
        );
      }
      const sleep = night.sleep;
      hits.add({
        shape: "circle",
        cx,
        cy,
        r: r + 6,
        title: formatDate(night.date),
        details: [
          { label: "Total", value: formatDuration(sleep.totalDuration) },
          { label: "Deep", value: formatDuration(sleep.deepSleep) },
          { label: "REM", value: formatDuration(sleep.remSleep) },
          { label: "Core", value: formatDuration(sleep.coreSleep) },
          ...sleep.awakeTime ? [{ label: "Awake", value: formatDuration(sleep.awakeTime) }] : [],
          {
            label: "Bedtime",
            value: /^\d{1,2}:\d{2}$/.test(sleep.bedtime) ? sleep.bedtime : new Date(sleep.bedtime).toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })
          },
          {
            label: "Wake",
            value: /^\d{1,2}:\d{2}$/.test(sleep.wakeTime) ? sleep.wakeTime : new Date(sleep.wakeTime).toLocaleTimeString("en-US", {
              hour: "numeric",
              minute: "2-digit"
            })
          }
        ],
        payload: night
      });
    });
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/step-spiral.ts
  var renderStepSpiral = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const cx = W / 2, cy = H / 2;
    const rx = W / 2 - 24;
    const ry = H / 2 - 24;
    const days = data.filter((d) => {
      var _a;
      return (_a = d.activity) == null ? void 0 : _a.steps;
    });
    if (!days.length) return;
    const maxSteps = Math.max(...days.map((d) => d.activity.steps));
    const maxDist = Math.max(
      ...days.map((d) => d.activity.walkingRunningDistanceKm || 0)
    );
    let totalSteps = 0;
    let bestDay = days[0];
    days.forEach((day, i) => {
      totalSteps += day.activity.steps;
      if (day.activity.steps > bestDay.activity.steps) bestDay = day;
      const t = i / days.length;
      const angle = t * Math.PI * 3.5 - Math.PI / 2;
      const spiralT = 0.15 + t * 0.85;
      const x = cx + Math.cos(angle) * rx * spiralT;
      const y = cy + Math.sin(angle) * ry * spiralT;
      const steps = day.activity.steps;
      const dist = day.activity.walkingRunningDistanceKm || 0;
      const dotSize = 10 + steps / maxSteps * 30;
      const distT = maxDist > 0 ? dist / maxDist : 0;
      const dotAlpha = lerp(0.35, 0.9, distT);
      ctx.shadowColor = hexToRgba(theme.colors.accent, 0.7);
      ctx.shadowBlur = dotSize;
      ctx.fillStyle = hexToRgba(theme.colors.accent, dotAlpha);
      ctx.beginPath();
      ctx.arc(x, y, dotSize / 2, 0, Math.PI * 2);
      ctx.fill();
      ctx.shadowBlur = 0;
      if (i > 0) {
        const pt = (i - 1) / days.length;
        const pa = pt * Math.PI * 3.5 - Math.PI / 2;
        const pst = 0.15 + pt * 0.85;
        const px = cx + Math.cos(pa) * rx * pst;
        const py = cy + Math.sin(pa) * ry * pst;
        ctx.strokeStyle = hexToRgba(theme.colors.accent, lerp(0.08, 0.25, distT));
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.moveTo(px, py);
        ctx.lineTo(x, y);
        ctx.stroke();
      }
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(
        String((/* @__PURE__ */ new Date(day.date + "T00:00:00")).getDate()),
        x,
        y + dotSize / 2 + 11
      );
      hits.add({
        shape: "circle",
        cx: x,
        cy: y,
        r: Math.max(dotSize / 2 + 4, 8),
        title: formatDate(day.date),
        details: [
          { label: "Steps", value: steps.toLocaleString() },
          { label: "Distance", value: `${dist.toFixed(2)} km` },
          ...day.activity.activeCalories ? [
            {
              label: "Calories",
              value: `${Math.round(day.activity.activeCalories)} kcal`
            }
          ] : [],
          ...day.activity.exerciseMinutes ? [
            {
              label: "Exercise",
              value: `${day.activity.exerciseMinutes} min`
            }
          ] : [],
          ...day.activity.flightsClimbed ? [
            {
              label: "Flights",
              value: `${day.activity.flightsClimbed}`
            }
          ] : []
        ],
        payload: day
      });
    });
    const avgSteps = Math.round(totalSteps / days.length);
    renderStatBoxes(statsEl, [
      {
        value: avgSteps.toLocaleString(),
        label: "Avg/day",
        color: theme.colors.accent
      },
      {
        value: bestDay.activity.steps.toLocaleString(),
        label: "Best day",
        color: theme.colors.accent
      }
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/oxygen-river.ts
  function getBloodOxygenValues(day) {
    var _a, _b, _c, _d, _e, _f, _g;
    if ((_b = (_a = day.vitals) == null ? void 0 : _a.bloodOxygenSamples) == null ? void 0 : _b.length) {
      return day.vitals.bloodOxygenSamples.map((s) => s.value || s.percent || 0);
    }
    const avg3 = (_e = (_c = day.vitals) == null ? void 0 : _c.bloodOxygenAvg) != null ? _e : (_d = day.vitals) == null ? void 0 : _d.bloodOxygenPercent;
    if (avg3 !== void 0) {
      const min = (_f = day.vitals) == null ? void 0 : _f.bloodOxygenMin;
      const max = (_g = day.vitals) == null ? void 0 : _g.bloodOxygenMax;
      if (min !== void 0 && max !== void 0 && min !== max) {
        return [min, avg3, max];
      }
      return [avg3];
    }
    return [];
  }
  var renderOxygenRiver = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const days = data.filter((d) => getBloodOxygenValues(d).length > 0);
    if (!days.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("No SpO2 data", W / 2, H / 2);
      return;
    }
    const allSamples = [];
    days.forEach((day, di) => {
      getBloodOxygenValues(day).forEach((v, i, arr) => {
        allSamples.push({
          x: di + (arr.length > 1 ? i / (arr.length - 1) * 0.8 : 0.4),
          value: v
        });
      });
    });
    const minO2 = Math.min(...allSamples.map((s) => s.value));
    const maxO2 = Math.max(...allSamples.map((s) => s.value));
    allSamples.forEach((s) => {
      const x = s.x / days.length * W;
      const t = (s.value - minO2) / (maxO2 - minO2 || 1);
      const y = H * 0.5 + (1 - t) * H * 0.35 - t * H * 0.35;
      const rSize = lerp(7, 3, t);
      const h = lerp(0, 210, t);
      ctx.fillStyle = hsl(h, lerp(80, 70, t), lerp(40, 50, t));
      ctx.globalAlpha = 0.55;
      ctx.beginPath();
      ctx.arc(x, y, rSize, 0, Math.PI * 2);
      ctx.fill();
    });
    ctx.globalAlpha = 1;
    const colW = W / days.length;
    days.forEach((day, di) => {
      const vals = getBloodOxygenValues(day);
      const dayMin = Math.min(...vals);
      const dayMax = Math.max(...vals);
      const dayAvg = vals.reduce((a, b) => a + b, 0) / vals.length;
      hits.add({
        shape: "rect",
        x: di * colW,
        y: 0,
        w: colW,
        h: H,
        title: formatDate(day.date),
        details: [
          { label: "Avg SpO\u2082", value: `${dayAvg.toFixed(1)}%` },
          { label: "Min", value: `${dayMin.toFixed(1)}%` },
          { label: "Max", value: `${dayMax.toFixed(1)}%` },
          { label: "Samples", value: `${vals.length}` }
        ],
        payload: day
      });
    });
    const avgO2 = allSamples.reduce((s, v) => s + v.value, 0) / allSamples.length;
    renderStatBoxes(statsEl, [
      { value: `${avgO2.toFixed(1)}%`, label: "Avg SpO2", color: "#4488ff" },
      { value: `${minO2.toFixed(1)}%`, label: "Min", color: "#6688cc" },
      { value: `${maxO2.toFixed(1)}%`, label: "Max", color: "#88aaee" }
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/breathing-wave.ts
  function getRespiratoryValues(day) {
    var _a, _b, _c, _d, _e, _f, _g;
    if ((_b = (_a = day.vitals) == null ? void 0 : _a.respiratoryRateSamples) == null ? void 0 : _b.length) {
      return day.vitals.respiratoryRateSamples.map((s) => s.value);
    }
    const avg3 = (_e = (_c = day.vitals) == null ? void 0 : _c.respiratoryRate) != null ? _e : (_d = day.vitals) == null ? void 0 : _d.respiratoryRateAvg;
    if (avg3 !== void 0) {
      const min = (_f = day.vitals) == null ? void 0 : _f.respiratoryRateMin;
      const max = (_g = day.vitals) == null ? void 0 : _g.respiratoryRateMax;
      if (min !== void 0 && max !== void 0 && min !== max) {
        return [min, avg3, max];
      }
      return [avg3];
    }
    return [];
  }
  var renderBreathingWave = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const days = data.filter((d) => getRespiratoryValues(d).length > 0);
    if (!days.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("No respiratory data", W / 2, H / 2);
      return;
    }
    const allVals = [];
    days.forEach((day) => allVals.push(...getRespiratoryValues(day)));
    const minR = Math.min(...allVals);
    const maxR = Math.max(...allVals);
    const grad = ctx.createLinearGradient(0, 0, 0, H);
    grad.addColorStop(0, hexToRgba(theme.colors.accent, 0.35));
    grad.addColorStop(1, hexToRgba(theme.colors.accent, 0));
    ctx.beginPath();
    ctx.moveTo(0, H);
    allVals.forEach((v, i) => {
      const x = i / allVals.length * W;
      const t = (v - minR) / (maxR - minR || 1);
      ctx.lineTo(x, H - 16 - t * (H - 32));
    });
    ctx.lineTo(W, H);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();
    ctx.beginPath();
    allVals.forEach((v, i) => {
      const x = i / allVals.length * W;
      const t = (v - minR) / (maxR - minR || 1);
      const y = H - 16 - t * (H - 32);
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    });
    ctx.strokeStyle = theme.colors.accent;
    ctx.lineWidth = 1.5;
    ctx.stroke();
    let sampleIdx = 0;
    days.forEach((day) => {
      const vals = getRespiratoryValues(day);
      const startIdx = sampleIdx;
      sampleIdx += vals.length;
      const x0 = startIdx / allVals.length * W;
      const x1 = sampleIdx / allVals.length * W;
      const dayAvg = vals.reduce((a, b) => a + b, 0) / vals.length;
      const dayMin = Math.min(...vals);
      const dayMax = Math.max(...vals);
      hits.add({
        shape: "rect",
        x: x0,
        y: 0,
        w: x1 - x0,
        h: H,
        title: formatDate(day.date),
        details: [
          { label: "Avg", value: `${dayAvg.toFixed(1)} br/min` },
          { label: "Min", value: `${dayMin.toFixed(1)}` },
          { label: "Max", value: `${dayMax.toFixed(1)}` },
          { label: "Samples", value: `${vals.length}` }
        ],
        payload: day
      });
    });
    const avg3 = (allVals.reduce((a, b) => a + b, 0) / allVals.length).toFixed(
      1
    );
    renderStatBoxes(statsEl, [
      { value: avg3, label: "Avg br/min", color: theme.colors.accent },
      { value: minR.toFixed(1), label: "Min", color: theme.muted },
      { value: maxR.toFixed(1), label: "Max", color: theme.colors.accent }
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/vitals-rings.ts
  var renderVitalsRings = (ctx, data, W, H, _config, theme, _statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const cx = W / 2, cy = H / 2;
    const days = data.filter((d) => d.activity && d.heart);
    if (!days.length) return;
    const maxSteps = Math.max(...days.map((d) => d.activity.steps || 0));
    const maxCal = Math.max(
      ...days.map((d) => d.activity.activeCalories || 0)
    );
    const maxHR = Math.max(
      ...days.map(
        (d) => d.heart.restingHeartRate || d.heart.averageHeartRate || 80
      )
    );
    const minHR = Math.min(
      ...days.map(
        (d) => d.heart.restingHeartRate || d.heart.averageHeartRate || 60
      )
    );
    const maxRx = W / 2 - 16;
    const maxRy = H / 2 - 16;
    const ringGap = Math.min(maxRx, maxRy) / days.length;
    const sx = maxRx / Math.max(maxRx, maxRy);
    const sy = maxRy / Math.max(maxRx, maxRy);
    days.forEach((day, i) => {
      const baseR = 16 + i * ringGap;
      const steps = day.activity.steps || 0;
      const cal = day.activity.activeCalories || 0;
      const hr = day.heart.restingHeartRate || day.heart.averageHeartRate || 70;
      const stepsAngle = steps / maxSteps * Math.PI * 2;
      ctx.save();
      ctx.translate(cx, cy);
      ctx.scale(
        sx > sy ? 1 : maxRx / maxRy,
        sy > sx ? 1 : maxRy / maxRx
      );
      ctx.strokeStyle = hexToRgba(theme.colors.accent, 0.25 + steps / maxSteps * 0.55);
      ctx.lineWidth = ringGap * 0.4;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.arc(0, 0, baseR, -Math.PI / 2, -Math.PI / 2 + stepsAngle);
      ctx.stroke();
      const calAngle = cal / maxCal * Math.PI * 2;
      ctx.strokeStyle = hexToRgba(theme.colors.secondary, 0.25 + cal / maxCal * 0.55);
      ctx.lineWidth = ringGap * 0.22;
      ctx.beginPath();
      ctx.arc(
        0,
        0,
        baseR + ringGap * 0.15,
        -Math.PI / 2,
        -Math.PI / 2 + calAngle
      );
      ctx.stroke();
      ctx.restore();
      const hrT = (hr - minHR) / (maxHR - minHR || 1);
      const dotAngle = -Math.PI / 2 + stepsAngle;
      const scaleX = sx > sy ? 1 : maxRx / maxRy;
      const scaleY = sy > sx ? 1 : maxRy / maxRx;
      const dx = cx + Math.cos(dotAngle) * baseR * scaleX;
      const dy = cy + Math.sin(dotAngle) * baseR * scaleY;
      ctx.fillStyle = hsl(lerp(200, 0, hrT), 80, 50);
      ctx.beginPath();
      ctx.arc(dx, dy, 3, 0, Math.PI * 2);
      ctx.fill();
      hits.add({
        shape: "circle",
        cx: dx,
        cy: dy,
        r: 8,
        title: formatDate(day.date),
        details: [
          { label: "Steps", value: steps.toLocaleString() },
          {
            label: "Calories",
            value: `${Math.round(cal)} kcal`
          },
          { label: "Resting HR", value: `${Math.round(hr)} bpm` },
          ...day.activity.exerciseMinutes ? [
            {
              label: "Exercise",
              value: `${day.activity.exerciseMinutes} min`
            }
          ] : []
        ],
        payload: day
      });
    });
    ctx.fillStyle = theme.muted;
    ctx.font = "9px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("inner \u2192 outer", cx, cy - 3);
    ctx.fillText("oldest \u2192 newest", cx, cy + 9);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/walking-symmetry.ts
  var renderWalkingSymmetry = (ctx, data, W, H, _config, theme, _statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const days = data.filter((d) => d.mobility);
    if (!days.length) return;
    const maxSpeed = Math.max(
      ...days.map((d) => d.mobility.walkingSpeed || 0)
    );
    const maxAsym = Math.max(
      ...days.map((d) => d.mobility.walkingAsymmetryPercentage || 0)
    );
    const barW = (W - 20) / days.length;
    const leftPad = 10;
    const midY = H / 2;
    days.forEach((day, i) => {
      const speed = day.mobility.walkingSpeed || 0;
      const asym = day.mobility.walkingAsymmetryPercentage || 0;
      const x = leftPad + i * barW;
      const speedH = maxSpeed > 0 ? speed / maxSpeed * (midY - 16) : 0;
      const sg = ctx.createLinearGradient(x, midY, x, midY - speedH);
      sg.addColorStop(0, hexToRgba(theme.colors.accent, 0.08));
      sg.addColorStop(1, hexToRgba(theme.colors.accent, 0.75));
      ctx.fillStyle = sg;
      ctx.beginPath();
      ctx.roundRect(x + 1, midY - speedH, barW - 2, speedH, [3, 3, 0, 0]);
      ctx.fill();
      const asymH = maxAsym > 0 ? asym / maxAsym * (midY - 16) : 0;
      const asymT = maxAsym > 0 ? asym / maxAsym : 0;
      const secRgb = hexToRgb(theme.colors.secondary);
      const heartRgb = hexToRgb(theme.colors.heart);
      const ag = ctx.createLinearGradient(x, midY, x, midY + asymH);
      ag.addColorStop(0, hexToRgba(theme.colors.secondary, 0.08));
      ag.addColorStop(
        1,
        `rgba(${Math.round(lerp(secRgb.r, heartRgb.r, asymT))},${Math.round(lerp(secRgb.g, heartRgb.g, asymT))},${Math.round(lerp(secRgb.b, heartRgb.b, asymT))},0.75)`
      );
      ctx.fillStyle = ag;
      ctx.beginPath();
      ctx.roundRect(x + 1, midY, barW - 2, asymH, [0, 0, 3, 3]);
      ctx.fill();
      const m = day.mobility;
      hits.add({
        shape: "rect",
        x,
        y: 0,
        w: barW,
        h: H,
        title: formatDate(day.date),
        details: [
          { label: "Speed", value: `${speed.toFixed(2)} m/s` },
          { label: "Asymmetry", value: `${asym.toFixed(1)}%` },
          ...m.walkingStepLength ? [
            {
              label: "Step length",
              value: `${m.walkingStepLength.toFixed(2)} m`
            }
          ] : [],
          ...m.walkingDoubleSupportPercentage ? [
            {
              label: "Double support",
              value: `${m.walkingDoubleSupportPercentage.toFixed(1)}%`
            }
          ] : []
        ],
        payload: day
      });
    });
    ctx.strokeStyle = theme.isDark ? "#222" : "#ddd";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(leftPad, midY);
    ctx.lineTo(W, midY);
    ctx.stroke();
    ctx.fillStyle = theme.muted;
    ctx.font = "8px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("\u2191 speed", W / 2, 12);
    ctx.fillText("\u2193 wobble", W / 2, H - 4);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/sleep-architecture.ts
  function buildSyntheticStages2(night) {
    var _a, _b, _c, _d;
    const sleep = night.sleep;
    if (!sleep.bedtime || !sleep.wakeTime) return [];
    const isTimeOnly = (s) => /^\d{1,2}:\d{2}$/.test(s);
    let bedMs;
    let wakeMs;
    if (isTimeOnly(sleep.bedtime)) {
      bedMs = (/* @__PURE__ */ new Date(`${night.date}T${sleep.bedtime}:00`)).getTime();
      wakeMs = (/* @__PURE__ */ new Date(`${night.date}T${sleep.wakeTime}:00`)).getTime();
      if (wakeMs <= bedMs) wakeMs += 864e5;
    } else {
      bedMs = Date.parse(sleep.bedtime);
      wakeMs = Date.parse(sleep.wakeTime);
    }
    if (!isFinite(bedMs) || !isFinite(wakeMs) || wakeMs <= bedMs) return [];
    const stages = [];
    let cursor = bedMs;
    function addStage(stage, secs) {
      if (secs <= 0) return;
      const startDate = new Date(cursor).toISOString();
      cursor += secs * 1e3;
      stages.push({ stage, startDate, endDate: new Date(cursor).toISOString(), durationSeconds: Math.round(secs) });
    }
    const awake = (_a = sleep.awakeTime) != null ? _a : 0;
    const core = (_b = sleep.coreSleep) != null ? _b : 0;
    const deep = (_c = sleep.deepSleep) != null ? _c : 0;
    const rem = (_d = sleep.remSleep) != null ? _d : 0;
    addStage("awake", awake * 0.3);
    addStage("core", core * 0.45);
    addStage("deep", deep);
    addStage("rem", rem);
    addStage("core", core * 0.55);
    addStage("awake", awake * 0.7);
    return stages;
  }
  function getEffectiveStages2(night) {
    var _a, _b;
    const stages = (_b = (_a = night.sleep) == null ? void 0 : _a.sleepStages) != null ? _b : [];
    if (stages.length > 0) return stages;
    return buildSyntheticStages2(night);
  }
  var renderSleepArchitecture = (ctx, data, W, H, _config, theme, _statsEl, hits) => {
    const canvas = ctx.canvas;
    const nights = data.filter(
      (d) => d.sleep && (d.sleep.sleepStages.length > 0 || d.sleep.totalDuration > 0)
    );
    if (!nights.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("No sleep data", W / 2, H / 2);
      return;
    }
    const stripeHeight = 48;
    const gap = 6;
    const labelWidth = 80;
    const rightPad = 20;
    const topPad = 10;
    const totalHeight = topPad + nights.length * (stripeHeight + gap);
    const dpr = activeWindow.devicePixelRatio || 1;
    canvas.width = W * dpr;
    canvas.height = totalHeight * dpr;
    canvas.style.width = W + "px";
    canvas.style.height = totalHeight + "px";
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.scale(dpr, dpr);
    const barWidth = W - labelWidth - rightPad;
    const nightMeta = nights.map((n) => {
      const stages = getEffectiveStages2(n);
      const start = new Date(stages[0].startDate).getTime();
      const end = new Date(stages[stages.length - 1].endDate).getTime();
      return { start, end, span: end - start, stages };
    });
    const maxSpan = Math.max(...nightMeta.map((m) => m.span));
    nights.forEach((night, i) => {
      const y = topPad + i * (stripeHeight + gap);
      const meta = nightMeta[i];
      const d = /* @__PURE__ */ new Date(night.date + "T00:00:00");
      const label = d.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        weekday: "short"
      });
      ctx.fillStyle = theme.muted;
      ctx.font = "11px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      ctx.fillText(label, labelWidth - 12, y + stripeHeight / 2);
      ctx.fillStyle = theme.isDark ? "#111118" : "#eeeef2";
      ctx.beginPath();
      ctx.roundRect(labelWidth, y, barWidth, stripeHeight, 4);
      ctx.fill();
      const nightSleep = night.sleep;
      hits.add({
        shape: "rect",
        x: labelWidth,
        y,
        w: barWidth,
        h: stripeHeight,
        title: formatDate(night.date),
        details: [
          { label: "Total", value: formatDuration(nightSleep.totalDuration) },
          { label: "Deep", value: formatDuration(nightSleep.deepSleep) },
          { label: "REM", value: formatDuration(nightSleep.remSleep) },
          { label: "Core", value: formatDuration(nightSleep.coreSleep) }
        ],
        payload: night
      });
      meta.stages.forEach((stage) => {
        const stageStart = new Date(stage.startDate).getTime();
        const stageEnd = new Date(stage.endDate).getTime();
        const x = labelWidth + (stageStart - meta.start) / maxSpan * barWidth;
        const w = Math.max(
          1,
          (stageEnd - stageStart) / maxSpan * barWidth
        );
        ctx.shadowColor = theme.colors.sleep[stage.stage] || "#000";
        ctx.shadowBlur = 8;
        ctx.fillStyle = theme.colors.sleep[stage.stage] || "#333";
        ctx.fillRect(x, y + 2, w, stripeHeight - 4);
        ctx.shadowBlur = 0;
        const fmtTime = (iso) => new Date(iso).toLocaleTimeString("en-US", {
          hour: "numeric",
          minute: "2-digit"
        });
        hits.add({
          shape: "rect",
          x,
          y: y + 2,
          w,
          h: stripeHeight - 4,
          title: `${stage.stage.toUpperCase()} \u2014 ${formatDate(night.date)}`,
          details: [
            { label: "Start", value: fmtTime(stage.startDate) },
            { label: "End", value: fmtTime(stage.endDate) },
            {
              label: "Duration",
              value: formatDuration(stage.durationSeconds)
            }
          ],
          payload: { day: night, stage }
        });
      });
    });
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/hrv-trend.ts
  var renderHrvTrend = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const days = data.filter(
      (d) => d.heart && (d.heart.hrv != null || d.heart.hrvSamples && d.heart.hrvSamples.length > 0)
    );
    if (!days.length) return;
    const padL = 36, padR = 16, padT = 16, padB = 28;
    const plotW2 = W - padL - padR;
    const plotH = H - padT - padB;
    const values = days.map((d) => {
      var _a;
      const heart = d.heart;
      if (!heart) return 0;
      if (heart.hrv != null) return heart.hrv;
      const samples = (_a = heart.hrvSamples) != null ? _a : [];
      return samples.reduce((s, x) => s + x.value, 0) / samples.length;
    });
    const minVal = Math.min(...values);
    const maxVal = Math.max(...values);
    const range = maxVal - minVal || 1;
    const xFor = (i) => padL + i / (days.length - 1 || 1) * plotW2;
    const yFor = (v) => padT + plotH - (v - minVal) / range * plotH;
    const gridCount = 4;
    ctx.strokeStyle = hexToRgba(theme.fg, 0.07);
    ctx.lineWidth = 1;
    for (let g = 0; g <= gridCount; g++) {
      const y = padT + g / gridCount * plotH;
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      const label = Math.round(maxVal - g / gridCount * range);
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.fillText(String(label), padL - 4, y + 3);
    }
    const grad = ctx.createLinearGradient(0, padT, 0, padT + plotH);
    grad.addColorStop(0, hexToRgba(theme.colors.secondary, 0.35));
    grad.addColorStop(1, hexToRgba(theme.colors.secondary, 0.02));
    ctx.beginPath();
    ctx.moveTo(xFor(0), padT + plotH);
    ctx.lineTo(xFor(0), yFor(values[0]));
    for (let i = 1; i < days.length; i++) {
      const x0 = xFor(i - 1), y0 = yFor(values[i - 1]);
      const x1 = xFor(i), y1 = yFor(values[i]);
      const mx = (x0 + x1) / 2;
      ctx.bezierCurveTo(mx, y0, mx, y1, x1, y1);
    }
    ctx.lineTo(xFor(days.length - 1), padT + plotH);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(xFor(0), yFor(values[0]));
    for (let i = 1; i < days.length; i++) {
      const x0 = xFor(i - 1), y0 = yFor(values[i - 1]);
      const x1 = xFor(i), y1 = yFor(values[i]);
      const mx = (x0 + x1) / 2;
      ctx.bezierCurveTo(mx, y0, mx, y1, x1, y1);
    }
    ctx.strokeStyle = hexToRgba(theme.colors.secondary, 0.9);
    ctx.lineWidth = 1.5;
    ctx.lineJoin = "round";
    ctx.stroke();
    days.forEach((day, i) => {
      var _a, _b;
      const x = xFor(i);
      const y = yFor(values[i]);
      ctx.beginPath();
      ctx.arc(x, y, 3.5, 0, Math.PI * 2);
      ctx.fillStyle = theme.colors.secondary;
      ctx.fill();
      hits.add({
        shape: "circle",
        cx: x,
        cy: y,
        r: 10,
        title: formatDate(day.date),
        details: [
          { label: "HRV", value: `${values[i].toFixed(1)} ms` },
          ...((_a = day.heart) == null ? void 0 : _a.restingHeartRate) ? [{ label: "Resting HR", value: `${day.heart.restingHeartRate} bpm` }] : [],
          ...((_b = day.heart) == null ? void 0 : _b.averageHeartRate) ? [{ label: "Avg HR", value: `${Math.round(day.heart.averageHeartRate)} bpm` }] : []
        ],
        payload: day
      });
    });
    const labelStep = Math.max(1, Math.floor(days.length / 5));
    ctx.fillStyle = theme.muted;
    ctx.font = "8px sans-serif";
    ctx.textAlign = "center";
    days.forEach((day, i) => {
      if (i % labelStep !== 0 && i !== days.length - 1) return;
      const d = /* @__PURE__ */ new Date(day.date + "T00:00:00");
      const label = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      ctx.fillText(label, xFor(i), H - 6);
    });
    const avg3 = values.reduce((s, v) => s + v, 0) / values.length;
    renderInlineStats(statsEl, [
      [
        { text: "Avg HRV " },
        { text: `${avg3.toFixed(1)} ms`, strong: true }
      ],
      [
        { text: "Min " },
        { text: minVal.toFixed(1), strong: true }
      ],
      [
        { text: "Max " },
        { text: maxVal.toFixed(1), strong: true }
      ]
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/activity-heatmap.ts
  var DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  var renderActivityHeatmap = (ctx, data, W, H, config, theme, statsEl, hits) => {
    var _a, _b, _c, _d;
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const days = data.filter((d) => d.activity);
    if (!days.length) return;
    const metric = (_a = config.metric) != null ? _a : "steps";
    const getValue = (d) => {
      if (!d.activity) return 0;
      if (metric === "calories") return d.activity.activeCalories || 0;
      if (metric === "distance") return d.activity.walkingRunningDistanceKm || 0;
      return d.activity.steps || 0;
    };
    const byDate = {};
    let firstDate = days[0].date;
    let lastDate = days[days.length - 1].date;
    for (const d of days) {
      byDate[d.date] = getValue(d);
      if (d.date < firstDate) firstDate = d.date;
      if (d.date > lastDate) lastDate = d.date;
    }
    const startDay = /* @__PURE__ */ new Date(firstDate + "T00:00:00");
    startDay.setDate(startDay.getDate() - startDay.getDay());
    const endDay = /* @__PURE__ */ new Date(lastDate + "T00:00:00");
    endDay.setDate(endDay.getDate() + (6 - endDay.getDay()));
    const totalDays = Math.round((endDay.getTime() - startDay.getTime()) / 864e5) + 1;
    const totalWeeks = Math.ceil(totalDays / 7);
    const padL = 28, padR = 8, padT = 20, padB = 8;
    const cellW = (W - padL - padR) / totalWeeks;
    const cellH = (H - padT - padB) / 7;
    const gap = Math.max(1.5, Math.min(cellW, cellH) * 0.12);
    const radius = Math.max(1, Math.min(cellW, cellH) * 0.18);
    const maxVal = Math.max(...Object.values(byDate), 1);
    ctx.fillStyle = theme.muted;
    ctx.font = "8px sans-serif";
    ctx.textAlign = "right";
    for (let dow = 0; dow < 7; dow++) {
      if (dow % 2 === 1) continue;
      const y = padT + dow * cellH + cellH / 2 + 3;
      ctx.fillText(DOW[dow], padL - 3, y);
    }
    let lastMonth = -1;
    let lastMonthLabelX = -Infinity;
    ctx.textAlign = "center";
    for (let w = 0; w < totalWeeks; w++) {
      const weekStart = new Date(startDay);
      weekStart.setDate(weekStart.getDate() + w * 7);
      const mo = weekStart.getMonth();
      const x = padL + w * cellW + cellW / 2;
      if (mo !== lastMonth && x - lastMonthLabelX >= 28) {
        lastMonth = mo;
        lastMonthLabelX = x;
        const label = weekStart.toLocaleDateString("en-US", { month: "short" });
        ctx.fillText(label, x, padT - 5);
      }
    }
    for (let w = 0; w < totalWeeks; w++) {
      for (let dow = 0; dow < 7; dow++) {
        const cellDate = new Date(startDay);
        cellDate.setDate(cellDate.getDate() + w * 7 + dow);
        const iso = cellDate.toISOString().slice(0, 10);
        const val = (_b = byDate[iso]) != null ? _b : null;
        const x = padL + w * cellW + gap / 2;
        const y = padT + dow * cellH + gap / 2;
        const cw = cellW - gap;
        const ch = cellH - gap;
        if (val === null) {
          ctx.strokeStyle = hexToRgba(theme.fg, 0.06);
          ctx.lineWidth = 0.5;
          ctx.beginPath();
          ctx.roundRect(x, y, cw, ch, radius);
          ctx.stroke();
          continue;
        }
        const t = Math.pow(val / maxVal, 0.6);
        ctx.fillStyle = hexToRgba(theme.colors.accent, 0.1 + t * 0.85);
        ctx.beginPath();
        ctx.roundRect(x, y, cw, ch, radius);
        ctx.fill();
        hits.add({
          shape: "rect",
          x,
          y,
          w: cw,
          h: ch,
          title: formatDate(iso),
          details: [
            { label: metric.charAt(0).toUpperCase() + metric.slice(1), value: formatMetric(metric, val) },
            ...byDate[iso] != null && metric !== "steps" && ((_d = (_c = days.find((d) => d.date === iso)) == null ? void 0 : _c.activity) == null ? void 0 : _d.steps) ? [{ label: "Steps", value: (days.find((d) => d.date === iso).activity.steps || 0).toLocaleString() }] : []
          ],
          payload: iso
        });
      }
    }
    const total = Object.values(byDate).reduce((s, v) => s + v, 0);
    const avg3 = total / Object.keys(byDate).length;
    const metricLabel = metric.charAt(0).toUpperCase() + metric.slice(1);
    renderInlineStats(statsEl, [
      [
        { text: `${metricLabel} \u2014 Avg ` },
        { text: formatMetric(metric, avg3), strong: true },
        { text: " \xB7 Max " },
        { text: formatMetric(metric, maxVal), strong: true },
        { text: " \xB7 Total " },
        { text: formatMetric(metric, total), strong: true }
      ]
    ]);
  };
  function formatMetric(metric, val) {
    if (metric === "calories") return `${Math.round(val).toLocaleString()} kcal`;
    if (metric === "distance") return `${val.toFixed(1)} km`;
    return Math.round(val).toLocaleString();
  }

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/sleep-quality-bars.ts
  var renderSleepQualityBars = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const days = data.filter((d) => d.sleep && d.sleep.totalDuration > 0);
    if (!days.length) return;
    const padL = 40, padR = 16, padT = 20, padB = 28;
    const plotW2 = W - padL - padR;
    const plotH = H - padT - padB;
    const maxTotal = Math.max(...days.map((d) => d.sleep.totalDuration));
    const barW = plotW2 / days.length;
    const gap = Math.max(1, barW * 0.15);
    const maxHours = Math.ceil(maxTotal / 3600);
    const gridStep = maxHours <= 8 ? 2 : 4;
    ctx.strokeStyle = hexToRgba(theme.fg, 0.07);
    ctx.lineWidth = 1;
    for (let h = 0; h <= maxHours; h += gridStep) {
      const y = padT + plotH - h / maxHours * plotH;
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.fillText(`${h}h`, padL - 4, y + 3);
    }
    const legend = [
      { label: "Deep", color: theme.colors.sleep.deep },
      { label: "REM", color: theme.colors.sleep.rem },
      { label: "Core", color: theme.colors.sleep.core },
      { label: "Awake", color: theme.colors.sleep.awake }
    ];
    let lx = padL;
    ctx.font = "8px sans-serif";
    ctx.textAlign = "left";
    for (const item of legend) {
      ctx.fillStyle = item.color;
      ctx.fillRect(lx, padT - 12, 8, 6);
      ctx.fillStyle = theme.muted;
      ctx.fillText(item.label, lx + 10, padT - 7);
      lx += 44;
    }
    const dateLabelStep = days.length <= 14 ? 1 : Math.max(1, Math.ceil(days.length / 6));
    days.forEach((day, i) => {
      const sl = day.sleep;
      const x = padL + i * barW + gap / 2;
      const bw = barW - gap;
      const segments = [
        { secs: sl.deepSleep || 0, color: theme.colors.sleep.deep, label: "Deep" },
        { secs: sl.remSleep || 0, color: theme.colors.sleep.rem, label: "REM" },
        { secs: sl.coreSleep || 0, color: theme.colors.sleep.core, label: "Core" },
        { secs: sl.awakeTime || 0, color: theme.colors.sleep.awake, label: "Awake" }
      ].filter((s) => s.secs > 0);
      let stackY = padT + plotH;
      segments.forEach(({ secs, color, label }, si) => {
        const segH = secs / maxTotal * plotH;
        stackY -= segH;
        const isTop = si === segments.length - 1;
        const r = isTop ? Math.min(3, bw / 4) : 0;
        ctx.fillStyle = hexToRgba(color, 0.85);
        ctx.beginPath();
        if (isTop) {
          ctx.roundRect(x, stackY, bw, segH, [r, r, 0, 0]);
        } else {
          ctx.rect(x, stackY, bw, segH);
        }
        ctx.fill();
        if (segH > 14 && bw > 28) {
          ctx.fillStyle = hexToRgba(theme.bg, 0.7);
          ctx.font = "7px sans-serif";
          ctx.textAlign = "center";
          ctx.fillText(label, x + bw / 2, stackY + segH / 2 + 2.5);
        }
      });
      if (i % dateLabelStep === 0 || i === days.length - 1) {
        const d = /* @__PURE__ */ new Date(day.date + "T00:00:00");
        const lbl = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
        ctx.fillStyle = theme.muted;
        ctx.font = "8px sans-serif";
        ctx.textAlign = "center";
        ctx.fillText(lbl, x + bw / 2, H - 6);
      }
      const barTop = padT + plotH - sl.totalDuration / maxTotal * plotH;
      hits.add({
        shape: "rect",
        x,
        y: barTop,
        w: bw,
        h: plotH - (barTop - padT),
        title: formatDate(day.date),
        details: [
          { label: "Total", value: formatDuration(sl.totalDuration) },
          ...sl.deepSleep ? [{ label: "Deep", value: formatDuration(sl.deepSleep) }] : [],
          ...sl.remSleep ? [{ label: "REM", value: formatDuration(sl.remSleep) }] : [],
          ...sl.coreSleep ? [{ label: "Core", value: formatDuration(sl.coreSleep) }] : [],
          ...sl.awakeTime ? [{ label: "Awake", value: formatDuration(sl.awakeTime) }] : [],
          ...sl.bedtime ? [{
            label: "Bedtime",
            value: new Date(sl.bedtime).toLocaleTimeString("en-US", {
              hour: "numeric",
              minute: "2-digit"
            })
          }] : []
        ],
        payload: day
      });
    });
    const avgTotal = days.reduce((s, d) => s + d.sleep.totalDuration, 0) / days.length;
    const avgDeep = days.reduce((s, d) => s + (d.sleep.deepSleep || 0), 0) / days.length;
    const avgRem = days.reduce((s, d) => s + (d.sleep.remSleep || 0), 0) / days.length;
    renderInlineStats(statsEl, [
      [
        { text: "Avg sleep " },
        { text: formatDuration(avgTotal), strong: true }
      ],
      [
        { text: "Avg deep " },
        { text: formatDuration(avgDeep), strong: true }
      ],
      [
        { text: "Avg REM " },
        { text: formatDuration(avgRem), strong: true }
      ]
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/workout-utils.ts
  function pickWorkout(data, config) {
    const dateKey = config.date != null ? String(config.date).trim() : "";
    const indexRaw = config.workout;
    const index = typeof indexRaw === "number" ? indexRaw : indexRaw != null ? parseInt(String(indexRaw), 10) : 0;
    const idx = Number.isFinite(index) && index >= 0 ? Math.floor(index) : 0;
    if (dateKey) {
      const day = data.find((d) => d.date === dateKey);
      if (!day || !day.workouts || !day.workouts.length) return null;
      const w = day.workouts[idx];
      if (!w) return null;
      return { day, workout: w, indexInDay: idx };
    }
    for (let i = data.length - 1; i >= 0; i--) {
      const day = data[i];
      if (day.workouts && day.workouts.length > idx) {
        return { day, workout: day.workouts[idx], indexInDay: idx };
      }
    }
    return null;
  }
  function resolveUnits(day) {
    var _a, _b;
    const unitSystem = (_b = (_a = day.unitSystem) != null ? _a : day.unit_system) != null ? _b : typeof day.units === "string" ? day.units : void 0;
    return unitSystem === "imperial" ? "imperial" : "metric";
  }
  function parseDistanceFormatted(value) {
    if (!value) return void 0;
    const match = /([-+]?\d*\.?\d+(?:e[-+]?\d+)?)/i.exec(value.replace(/,/g, ""));
    if (!match) return void 0;
    const n = Number(match[1]);
    if (!Number.isFinite(n)) return void 0;
    const normalized = value.toLowerCase();
    if (/\bkm\b/.test(normalized)) return n * 1e3;
    if (/\bmi\b|miles?\b/.test(normalized)) return n * 1609.344;
    if (/\byd\b|yards?\b/.test(normalized)) return n * 0.9144;
    if (/\bm\b|meters?\b/.test(normalized)) return n;
    return void 0;
  }
  function workoutDistanceMeters(workout) {
    if (workout.distanceMeters != null) return workout.distanceMeters;
    if (workout.distanceKm != null) return workout.distanceKm * 1e3;
    if (workout.distanceMi != null) return workout.distanceMi * 1609.344;
    const formattedMeters = parseDistanceFormatted(workout.distanceFormatted);
    if (formattedMeters != null) return formattedMeters;
    if (workout.distance == null) return void 0;
    return workout.distance > 100 ? workout.distance : workout.distance * 1e3;
  }
  function formatDistance(meters, day, preFormatted) {
    if (preFormatted) return preFormatted;
    if (resolveUnits(day) === "imperial") {
      const mi = meters / 1609.344;
      return mi >= 10 ? `${mi.toFixed(1)} mi` : `${mi.toFixed(2)} mi`;
    }
    const km = meters / 1e3;
    return km >= 10 ? `${km.toFixed(1)} km` : `${km.toFixed(2)} km`;
  }
  function formatWorkoutDistance(workout, day) {
    const meters = workoutDistanceMeters(workout);
    return meters == null ? void 0 : formatDistance(meters, day, workout.distanceFormatted);
  }
  function intervalRateDisplay(interval) {
    var _a;
    return (_a = interval.paceFormatted) != null ? _a : interval.speedFormatted;
  }
  function formatPace(meters, seconds, day, preFormatted) {
    if (preFormatted) return preFormatted;
    if (!meters || !seconds) return "\u2014";
    const unitDistance = resolveUnits(day) === "imperial" ? 1609.344 : 1e3;
    const secPerUnit = seconds / (meters / unitDistance);
    const m = Math.floor(secPerUnit / 60);
    const s = Math.round(secPerUnit % 60);
    const suffix = resolveUnits(day) === "imperial" ? "/mi" : "/km";
    return `${m}:${s.toString().padStart(2, "0")}${suffix}`;
  }
  function formatElevation(meters, day) {
    if (resolveUnits(day) === "imperial") {
      return `${Math.round(meters * 3.28084)} ft`;
    }
    return `${Math.round(meters)} m`;
  }
  function elapsedSeconds(startTime, sampleTimestamp) {
    if (!startTime) return NaN;
    const start = Date.parse(startTime);
    const sample = Date.parse(sampleTimestamp);
    if (!Number.isFinite(start) || !Number.isFinite(sample)) return NaN;
    return (sample - start) / 1e3;
  }
  function formatElapsed(seconds) {
    if (!Number.isFinite(seconds) || seconds < 0) return "\u2014";
    const h = Math.floor(seconds / 3600);
    const m = Math.floor(seconds % 3600 / 60);
    const s = Math.floor(seconds % 60);
    const pad = (n) => n.toString().padStart(2, "0");
    if (h > 0) return `${h}:${pad(m)}:${pad(s)}`;
    return `${m}:${pad(s)}`;
  }
  function drawEmptyState(ctx, w, h, bg, muted, message) {
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = muted;
    ctx.font = "12px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(message, w / 2, h / 2);
  }

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/workout-log.ts
  var TYPE_LABELS = {
    running: "Run",
    cycling: "Bike",
    walking: "Walk",
    swimming: "Swim",
    hiking: "Hike",
    yoga: "Yoga",
    strength: "Lift",
    "strength training": "Lift",
    elliptical: "Elli",
    rowing: "Row",
    pilates: "Pil",
    "high intensity interval training": "HIIT",
    hiit: "HIIT",
    tennis: "Ten",
    basketball: "Bball",
    soccer: "Soccer",
    dance: "Dance",
    "core training": "Core",
    "functional strength training": "Func"
  };
  function shortLabel(type) {
    var _a;
    const lower = type.toLowerCase().trim();
    return (_a = TYPE_LABELS[lower]) != null ? _a : type.slice(0, 5);
  }
  function typeColorIndex(type) {
    let hash = 0;
    for (let i = 0; i < type.length; i++) hash = hash * 31 + type.charCodeAt(i) & 65535;
    return hash % 6;
  }
  var HUE_OFFSETS = [0, 40, 80, 160, 210, 280];
  var renderWorkoutLog = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const entries = [];
    for (const day of data) {
      if (!day.workouts) continue;
      for (const w of day.workouts) {
        if (!w.duration) continue;
        entries.push({
          date: day.date,
          type: w.activityType || w.type || "Workout",
          duration: w.duration,
          calories: w.calories || 0,
          distanceMeters: workoutDistanceMeters(w),
          durationFormatted: w.durationFormatted,
          distanceFormatted: formatWorkoutDistance(w, day),
          avgHeartRate: w.avgHeartRate,
          avgPower: w.avgPower
        });
      }
    }
    if (!entries.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("No workouts in range", W / 2, H / 2);
      return;
    }
    const padL = 40, padR = 16, padT = 12, padB = 8;
    const plotW2 = W - padL - padR;
    const maxDuration = Math.max(...entries.map((e) => e.duration));
    const rowH = 28;
    const hasOverflow = entries.length * rowH > H - padT - padB;
    const footerH = hasOverflow ? 14 : 0;
    const visibleCount = Math.max(
      1,
      Math.min(entries.length, Math.floor((H - padT - padB - footerH) / rowH))
    );
    const visible = entries.slice(0, visibleCount);
    const barH = rowH * 0.55;
    const gap = (rowH - barH) / 2;
    const radius = barH / 3;
    const maxMin = Math.ceil(maxDuration / 60);
    const tickStep = maxMin <= 60 ? 15 : maxMin <= 120 ? 30 : 60;
    ctx.strokeStyle = hexToRgba(theme.fg, 0.07);
    ctx.lineWidth = 1;
    ctx.fillStyle = theme.muted;
    ctx.font = "8px sans-serif";
    ctx.textAlign = "center";
    for (let t = 0; t <= maxMin; t += tickStep) {
      const x = padL + t / maxMin * plotW2;
      ctx.beginPath();
      ctx.moveTo(x, padT);
      ctx.lineTo(x, padT + visible.length * rowH);
      ctx.stroke();
      ctx.fillText(`${t}m`, x, padT - 2);
    }
    visible.forEach((entry, i) => {
      var _a, _b;
      const y = padT + i * rowH + gap;
      const barW = entry.duration / (maxMin * 60) * plotW2;
      const ci = typeColorIndex(entry.type);
      const hue = HUE_OFFSETS[ci];
      const barColor = `hsl(${hue},60%,${theme.isDark ? 55 : 42}%)`;
      ctx.fillStyle = hexToRgba(barColor, 0.8);
      ctx.beginPath();
      ctx.roundRect(padL, y, Math.max(barW, 4), barH, radius);
      ctx.fill();
      ctx.fillStyle = theme.muted;
      ctx.font = "8px sans-serif";
      ctx.textAlign = "right";
      const d = /* @__PURE__ */ new Date(entry.date + "T00:00:00");
      const dateStr = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      ctx.fillText(dateStr, padL - 3, y + barH / 2 + 3);
      ctx.fillStyle = barW > 30 ? hexToRgba(theme.bg, 0.8) : theme.fg;
      ctx.font = `bold 7px sans-serif`;
      ctx.textAlign = barW > 30 ? "left" : "left";
      ctx.fillText(shortLabel(entry.type), barW > 30 ? padL + 4 : padL + barW + 4, y + barH / 2 + 2.5);
      hits.add({
        shape: "rect",
        x: padL,
        y,
        w: Math.max(barW, 24),
        h: barH,
        title: `${formatDate(entry.date)} \u2014 ${entry.type}`,
        details: [
          { label: "Duration", value: (_a = entry.durationFormatted) != null ? _a : formatDuration(entry.duration) },
          ...entry.calories ? [{ label: "Calories", value: `${Math.round(entry.calories)} kcal` }] : [],
          ...entry.distanceMeters != null ? [{ label: "Distance", value: (_b = entry.distanceFormatted) != null ? _b : `${(entry.distanceMeters / 1e3).toFixed(2)} km` }] : [],
          ...entry.avgHeartRate != null ? [{ label: "Avg HR", value: `${Math.round(entry.avgHeartRate)} BPM` }] : [],
          ...entry.avgPower != null ? [{ label: "Avg Power", value: `${Math.round(entry.avgPower)} W` }] : []
        ],
        payload: entry
      });
    });
    if (entries.length > visibleCount) {
      ctx.fillStyle = theme.muted;
      ctx.font = "8px sans-serif";
      ctx.textAlign = "left";
      ctx.fillText(`+${entries.length - visibleCount} more \u2014 increase height to see all`, padL, H - 2);
    }
    const totalDur = entries.reduce((s, e) => s + e.duration, 0);
    const totalCal = entries.reduce((s, e) => s + e.calories, 0);
    const types = [...new Set(entries.map((e) => e.type))];
    const statRows = [
      [{ text: `${entries.length} workouts` }],
      [
        { text: "Total time " },
        { text: formatDuration(totalDur), strong: true }
      ],
      [
        { text: "Types: " },
        { text: `${types.slice(0, 4).join(", ")}${types.length > 4 ? "\u2026" : ""}`, strong: true }
      ]
    ];
    if (totalCal) {
      statRows.splice(2, 0, [
        { text: "Total cal " },
        { text: `${Math.round(totalCal).toLocaleString()} kcal`, strong: true }
      ]);
    }
    renderInlineStats(statsEl, statRows);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/intro-stats.ts
  var renderIntroStats = (data, el, _config, theme) => {
    const totalSteps = data.reduce((s, d) => {
      var _a;
      return s + (((_a = d.activity) == null ? void 0 : _a.steps) || 0);
    }, 0);
    const totalDist = data.reduce(
      (s, d) => {
        var _a;
        return s + (((_a = d.activity) == null ? void 0 : _a.walkingRunningDistanceKm) || 0);
      },
      0
    );
    const heartDays = data.filter((d) => d.heart);
    const avgHR = heartDays.length ? heartDays.reduce((s, d) => s + (d.heart.averageHeartRate || 0), 0) / heartDays.length : 0;
    const sleepNights = data.filter(
      (d) => d.sleep && (d.sleep.sleepStages.length > 0 || d.sleep.totalDuration > 0)
    ).length;
    el.addClass("health-md-intro-grid");
    const stats = [
      { value: `${Math.round(avgHR)}`, label: "Avg BPM", color: theme.colors.heart },
      {
        value: `${(totalSteps / 1e3).toFixed(0)}k`,
        label: "Total Steps",
        color: theme.colors.accent
      },
      {
        value: `${sleepNights}`,
        label: "Nights Tracked",
        color: theme.colors.sleep.rem
      },
      {
        value: `${totalDist.toFixed(0)}km`,
        label: "Distance",
        color: theme.colors.secondary
      }
    ];
    stats.forEach((stat) => {
      const box = el.createDiv({ cls: "health-md-intro-stat" });
      const valEl = box.createDiv({ cls: "health-md-intro-value" });
      valEl.style.color = stat.color;
      valEl.textContent = stat.value;
      const labelEl = box.createDiv({ cls: "health-md-intro-label" });
      labelEl.style.color = theme.muted;
      labelEl.textContent = stat.label;
    });
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/summary-card.ts
  var METRICS = {
    "heart-rate": {
      category: "HEART",
      color: "#fa114f",
      unit: "BPM",
      decimals: 0,
      extract: (d) => {
        var _a;
        const v = (_a = d.heart) == null ? void 0 : _a.averageHeartRate;
        return v && v > 0 ? v : null;
      },
      min: (d) => {
        var _a, _b;
        return (_b = (_a = d.heart) == null ? void 0 : _a.heartRateMin) != null ? _b : null;
      },
      max: (d) => {
        var _a, _b;
        return (_b = (_a = d.heart) == null ? void 0 : _a.heartRateMax) != null ? _b : null;
      }
    },
    "steps": {
      category: "ACTIVITY",
      color: "#ff8e00",
      unit: "STEPS",
      decimals: 0,
      extract: (d) => {
        var _a;
        const v = (_a = d.activity) == null ? void 0 : _a.steps;
        return v != null && v > 0 ? v : null;
      }
    },
    "sleep-duration": {
      category: "SLEEP",
      color: "#715afc",
      unit: "H",
      decimals: 1,
      extract: (d) => {
        var _a;
        const v = (_a = d.sleep) == null ? void 0 : _a.totalDuration;
        return v != null && v > 0 ? v / 3600 : null;
      }
    },
    "active-calories": {
      category: "ACTIVITY",
      color: "#ff8e00",
      unit: "CAL",
      decimals: 0,
      extract: (d) => {
        var _a;
        const v = (_a = d.activity) == null ? void 0 : _a.activeCalories;
        return v != null && v > 0 ? v : null;
      }
    },
    "hrv": {
      category: "HEART",
      color: "#fa114f",
      unit: "MS",
      decimals: 0,
      extract: (d) => {
        var _a, _b;
        if (((_a = d.heart) == null ? void 0 : _a.hrv) != null) return d.heart.hrv;
        const samples = (_b = d.heart) == null ? void 0 : _b.hrvSamples;
        if (samples && samples.length > 0) {
          return samples.reduce((s, x) => s + x.value, 0) / samples.length;
        }
        return null;
      }
    },
    "blood-oxygen": {
      category: "RESPIRATORY",
      color: "#1eeaef",
      unit: "%",
      decimals: 1,
      extract: (d) => {
        var _a, _b, _c, _d;
        return (_d = (_c = (_a = d.vitals) == null ? void 0 : _a.bloodOxygenAvg) != null ? _c : (_b = d.vitals) == null ? void 0 : _b.bloodOxygenPercent) != null ? _d : null;
      },
      min: (d) => {
        var _a, _b;
        return (_b = (_a = d.vitals) == null ? void 0 : _a.bloodOxygenMin) != null ? _b : null;
      },
      max: (d) => {
        var _a, _b;
        return (_b = (_a = d.vitals) == null ? void 0 : _a.bloodOxygenMax) != null ? _b : null;
      }
    },
    "respiratory-rate": {
      category: "RESPIRATORY",
      color: "#3bb2c1",
      unit: "BRPM",
      decimals: 1,
      extract: (d) => {
        var _a, _b, _c, _d;
        return (_d = (_c = (_a = d.vitals) == null ? void 0 : _a.respiratoryRateAvg) != null ? _c : (_b = d.vitals) == null ? void 0 : _b.respiratoryRate) != null ? _d : null;
      },
      min: (d) => {
        var _a, _b;
        return (_b = (_a = d.vitals) == null ? void 0 : _a.respiratoryRateMin) != null ? _b : null;
      },
      max: (d) => {
        var _a, _b;
        return (_b = (_a = d.vitals) == null ? void 0 : _a.respiratoryRateMax) != null ? _b : null;
      }
    }
  };
  function splitWindows(data, compareWindow) {
    if (compareWindow === "week") {
      if (data.length < 14) return { current: data, prior: [], label: "vs prior week" };
      return { current: data.slice(-7), prior: data.slice(-14, -7), label: "vs prior week" };
    }
    if (compareWindow === "month") {
      if (data.length < 60) return { current: data, prior: [], label: "vs prior month" };
      return { current: data.slice(-30), prior: data.slice(-60, -30), label: "vs prior month" };
    }
    if (data.length < 2) return { current: data, prior: [], label: "vs prior period" };
    const mid = Math.floor(data.length / 2);
    return { current: data.slice(mid), prior: data.slice(0, mid), label: "vs prior period" };
  }
  function avg(nums) {
    return nums.reduce((s, n) => s + n, 0) / nums.length;
  }
  function formatValue(v, meta) {
    if (meta.unit === "STEPS" || meta.unit === "CAL") {
      return Math.round(v).toLocaleString();
    }
    if (meta.unit === "H") {
      const h = Math.floor(v);
      const m = Math.round((v - h) * 60);
      return `${h}h ${m}m`;
    }
    return v.toFixed(meta.decimals);
  }
  function buildSparkline(values, color, isDark) {
    if (values.length < 2) return "";
    const min = Math.min(...values);
    const max = Math.max(...values);
    const range = max - min || 1;
    const W = 100;
    const H = 28;
    const padY = 3;
    const plotH = H - padY * 2;
    const xFor = (i) => i / (values.length - 1) * W;
    const yFor = (v) => padY + plotH - (v - min) / range * plotH;
    let linePath = `M ${xFor(0).toFixed(2)} ${yFor(values[0]).toFixed(2)}`;
    for (let i = 1; i < values.length; i++) {
      const x0 = xFor(i - 1), y0 = yFor(values[i - 1]);
      const x1 = xFor(i), y1 = yFor(values[i]);
      const mx = (x0 + x1) / 2;
      linePath += ` C ${mx.toFixed(2)} ${y0.toFixed(2)}, ${mx.toFixed(2)} ${y1.toFixed(2)}, ${x1.toFixed(2)} ${y1.toFixed(2)}`;
    }
    const fillPath = `${linePath} L ${W} ${H} L 0 ${H} Z`;
    const gradId = `hmd-spark-${Math.random().toString(36).slice(2, 8)}`;
    const topAlpha = isDark ? 0.45 : 0.38;
    const botAlpha = 0.02;
    return `
		<svg class="health-md-summary-spark-svg" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">
			<defs>
				<linearGradient id="${gradId}" x1="0" y1="0" x2="0" y2="1">
					<stop offset="0%" stop-color="${color}" stop-opacity="${topAlpha}"/>
					<stop offset="100%" stop-color="${color}" stop-opacity="${botAlpha}"/>
				</linearGradient>
			</defs>
			<path d="${fillPath}" fill="url(#${gradId})"/>
			<path d="${linePath}" fill="none" stroke="${color}" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>
		</svg>
	`;
  }
  var renderSummaryCard = (data, el, config, theme) => {
    var _a, _b;
    const metricId = config.metric || "heart-rate";
    const meta = METRICS[metricId];
    if (!meta) {
      el.createEl("p", {
        text: `Unknown metric: ${metricId}`,
        cls: "health-md-error"
      });
      return;
    }
    const compareWindow = String(config.compareWindow || "same-length");
    const { current, prior, label: compareLabel } = splitWindows(data, compareWindow);
    const currentVals = current.map((day) => meta.extract(day)).filter((v) => v != null);
    if (!currentVals.length) {
      el.createEl("p", {
        text: `No ${metricId} data in range.`,
        cls: "health-md-error"
      });
      return;
    }
    const priorVals = prior.map((day) => meta.extract(day)).filter((v) => v != null);
    const card = el.createDiv({ cls: "health-md-summary-card" });
    card.style.setProperty("--hmd-summary-color", meta.color);
    card.style.borderColor = hexToRgba(theme.fg, 0.12);
    const pill = card.createDiv({ cls: "health-md-summary-pill" });
    pill.textContent = meta.category;
    pill.style.color = meta.color;
    const mainAvg = avg(currentVals);
    const kpi = card.createDiv({ cls: "health-md-summary-kpi" });
    kpi.createSpan({
      cls: "health-md-summary-value",
      text: formatValue(mainAvg, meta)
    });
    if (meta.unit !== "H") {
      const unitEl = kpi.createSpan({
        cls: "health-md-summary-unit",
        text: meta.unit
      });
      unitEl.style.color = theme.muted;
    }
    const sparkHtml = buildSparkline(currentVals, meta.color, theme.isDark);
    if (sparkHtml) {
      const sparkWrap = card.createDiv({ cls: "health-md-summary-spark" });
      appendSvgFromMarkup(sparkWrap, sparkHtml);
    }
    if (priorVals.length) {
      const priorAvg = avg(priorVals);
      const delta = priorAvg === 0 ? 0 : (mainAvg - priorAvg) / priorAvg * 100;
      const arrow = Math.abs(delta) < 0.5 ? "\u2014" : delta > 0 ? "\u25B2" : "\u25BC";
      const trendColor = Math.abs(delta) < 0.5 ? theme.muted : delta > 0 ? "#30c26a" : "#ff3b30";
      const trend = card.createDiv({ cls: "health-md-summary-trend" });
      const arrowEl = trend.createSpan({
        cls: "health-md-summary-arrow",
        text: arrow
      });
      arrowEl.style.color = trendColor;
      const deltaEl = trend.createSpan({
        cls: "health-md-summary-delta",
        text: `${Math.abs(delta).toFixed(Math.abs(delta) < 10 ? 1 : 0)}%`
      });
      deltaEl.style.color = trendColor;
      const captionEl = trend.createSpan({
        cls: "health-md-summary-caption",
        text: compareLabel
      });
      captionEl.style.color = theme.muted;
    }
    const minFn = (_a = meta.min) != null ? _a : ((d) => meta.extract(d));
    const maxFn = (_b = meta.max) != null ? _b : ((d) => meta.extract(d));
    const mins = current.map((day) => minFn(day)).filter((v) => v != null && v > 0);
    const maxs = current.map((day) => maxFn(day)).filter((v) => v != null && v > 0);
    if (mins.length && maxs.length) {
      const rangeEl = card.createDiv({ cls: "health-md-summary-meta" });
      rangeEl.style.color = theme.muted;
      const lo = Math.min(...mins);
      const hi = Math.max(...maxs);
      rangeEl.textContent = `Range ${formatValue(lo, meta)}\u2013${formatValue(hi, meta)} ${meta.unit === "H" ? "" : meta.unit}`.trim();
    }
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/trend-tile.ts
  var METRICS2 = {
    "resting-heart-rate": {
      category: "HEART",
      color: "#fa114f",
      label: "Resting Heart Rate",
      unit: "bpm",
      decimals: 0,
      higherIsBetter: false,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.heart) == null ? void 0 : _a.restingHeartRate) != null ? _b : null;
      }
    },
    "hrv": {
      category: "HEART",
      color: "#fa114f",
      label: "Heart Rate Variability",
      unit: "ms",
      decimals: 1,
      higherIsBetter: true,
      extract: (d) => {
        var _a, _b;
        if (((_a = d.heart) == null ? void 0 : _a.hrv) != null) return d.heart.hrv;
        const s = (_b = d.heart) == null ? void 0 : _b.hrvSamples;
        if (s && s.length) return s.reduce((acc, x) => acc + x.value, 0) / s.length;
        return null;
      }
    },
    "steps": {
      category: "ACTIVITY",
      color: "#ff8e00",
      label: "Steps",
      unit: "steps",
      decimals: 0,
      higherIsBetter: true,
      extract: (d) => {
        var _a, _b;
        return ((_b = (_a = d.activity) == null ? void 0 : _a.steps) != null ? _b : 0) > 0 ? d.activity.steps : null;
      }
    },
    "vo2max": {
      category: "HEART",
      color: "#fa114f",
      label: "Cardio Fitness",
      unit: "ml/kg\xB7min",
      decimals: 1,
      higherIsBetter: true,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.activity) == null ? void 0 : _a.vo2Max) != null ? _b : null;
      }
    },
    "walking-speed": {
      category: "ACTIVITY",
      color: "#ff8e00",
      label: "Walking Speed",
      unit: "m/s",
      decimals: 2,
      higherIsBetter: true,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.mobility) == null ? void 0 : _a.walkingSpeed) != null ? _b : null;
      }
    },
    "sleep-duration": {
      category: "SLEEP",
      color: "#715afc",
      label: "Sleep Duration",
      unit: "h",
      decimals: 1,
      higherIsBetter: true,
      extract: (d) => {
        var _a;
        const v = (_a = d.sleep) == null ? void 0 : _a.totalDuration;
        return v != null && v > 0 ? v / 3600 : null;
      }
    },
    "active-calories": {
      category: "ACTIVITY",
      color: "#ff8e00",
      label: "Active Energy",
      unit: "CAL",
      decimals: 0,
      higherIsBetter: true,
      extract: (d) => {
        var _a, _b;
        return ((_b = (_a = d.activity) == null ? void 0 : _a.activeCalories) != null ? _b : 0) > 0 ? d.activity.activeCalories : null;
      }
    }
  };
  function avg2(nums) {
    return nums.reduce((s, n) => s + n, 0) / nums.length;
  }
  function formatValue2(v, meta) {
    if (meta.unit === "steps") return Math.round(v).toLocaleString();
    if (meta.unit === "CAL") return `${Math.round(v)}`;
    if (meta.unit === "h") {
      const h = Math.floor(v);
      const m = Math.round((v - h) * 60);
      return `${h}h ${m}m`;
    }
    return v.toFixed(meta.decimals);
  }
  function buildSparkline2(current, prior, color, isDark) {
    if (!current.length) return "";
    const W = 120, H = 36, padY = 3;
    const plotH = H - padY * 2;
    const combined = [...prior, ...current];
    const min = Math.min(...combined);
    const max = Math.max(...combined);
    const range = max - min || 1;
    function pathFor(values, offsetFrac, widthFrac) {
      if (values.length < 2) return "";
      const x0 = offsetFrac * W;
      const x1 = (offsetFrac + widthFrac) * W;
      const xFor = (i) => x0 + i / (values.length - 1) * (x1 - x0);
      const yFor = (v) => padY + plotH - (v - min) / range * plotH;
      let p = `M ${xFor(0).toFixed(2)} ${yFor(values[0]).toFixed(2)}`;
      for (let i = 1; i < values.length; i++) {
        const px0 = xFor(i - 1), py0 = yFor(values[i - 1]);
        const px1 = xFor(i), py1 = yFor(values[i]);
        const mx = (px0 + px1) / 2;
        p += ` C ${mx.toFixed(2)} ${py0.toFixed(2)}, ${mx.toFixed(2)} ${py1.toFixed(2)}, ${px1.toFixed(2)} ${py1.toFixed(2)}`;
      }
      return p;
    }
    const priorFrac = prior.length / (prior.length + current.length || 1);
    const priorPath = pathFor(prior, 0, priorFrac);
    const currentPath = pathFor(current, priorFrac, 1 - priorFrac);
    const priorAlpha = isDark ? 0.4 : 0.35;
    return `
		<svg class="health-md-summary-spark-svg" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">
			${priorPath ? `<path d="${priorPath}" fill="none" stroke="${color}" stroke-opacity="${priorAlpha}" stroke-width="1.25" stroke-dasharray="3 2" vector-effect="non-scaling-stroke"/>` : ""}
			${currentPath ? `<path d="${currentPath}" fill="none" stroke="${color}" stroke-width="1.5" vector-effect="non-scaling-stroke"/>` : ""}
		</svg>
	`;
  }
  function splitWindows2(data, currentWindow, priorWindow) {
    if (data.length < currentWindow + 1) {
      const mid = Math.floor(data.length / 2);
      return { current: data.slice(mid), prior: data.slice(0, mid) };
    }
    const current = data.slice(-currentWindow);
    const priorEnd = data.length - currentWindow;
    const priorStart = Math.max(0, priorEnd - priorWindow);
    const prior = data.slice(priorStart, priorEnd);
    return { current, prior };
  }
  function narrative(meta, delta, windowDays) {
    const absPct = Math.abs(delta);
    if (absPct < 1) {
      return `Your ${meta.label.toLowerCase()} has been steady over the past ${windowDays} days.`;
    }
    const direction = delta > 0 ? "higher" : "lower";
    return `Your ${meta.label.toLowerCase()} is ${direction} than it was ${windowDays} days ago.`;
  }
  var renderTrendTile = (data, el, config, theme) => {
    const metricId = config.metric || "resting-heart-rate";
    const meta = METRICS2[metricId];
    if (!meta) {
      el.createEl("p", {
        text: `Unknown metric: ${metricId}`,
        cls: "health-md-error"
      });
      return;
    }
    const currentWindow = Number(config.currentWindow) || 90;
    const priorWindow = Number(config.priorWindow) || 90;
    const { current, prior } = splitWindows2(data, currentWindow, priorWindow);
    const currentVals = current.map((day) => meta.extract(day)).filter((v) => v != null);
    const priorVals = prior.map((day) => meta.extract(day)).filter((v) => v != null);
    if (!currentVals.length) {
      el.createEl("p", {
        text: `No ${meta.label.toLowerCase()} data in range.`,
        cls: "health-md-error"
      });
      return;
    }
    const card = el.createDiv({ cls: "health-md-summary-card health-md-trend-tile" });
    card.style.setProperty("--hmd-summary-color", meta.color);
    card.style.borderColor = hexToRgba(theme.fg, 0.12);
    const header = card.createDiv({ cls: "health-md-trend-header" });
    const pill = header.createSpan({ cls: "health-md-summary-pill" });
    pill.textContent = meta.category;
    pill.style.color = meta.color;
    const nameEl = header.createSpan({ cls: "health-md-trend-name" });
    nameEl.textContent = meta.label;
    nameEl.style.color = theme.fg;
    const currentAvg = avg2(currentVals);
    const priorAvg = priorVals.length ? avg2(priorVals) : null;
    const delta = priorAvg == null || priorAvg === 0 ? 0 : (currentAvg - priorAvg) / priorAvg * 100;
    const isImprovement = Math.abs(delta) >= 0.5 && (meta.higherIsBetter ? delta > 0 : delta < 0);
    const isRegression = Math.abs(delta) >= 0.5 && (meta.higherIsBetter ? delta < 0 : delta > 0);
    const arrow = Math.abs(delta) < 0.5 ? "\u2192" : delta > 0 ? "\u2191" : "\u2193";
    const arrowColor = isImprovement ? "#30c26a" : isRegression ? "#ff3b30" : theme.muted;
    const deltaRow = card.createDiv({ cls: "health-md-trend-delta-row" });
    const arrowEl = deltaRow.createSpan({ cls: "health-md-trend-arrow" });
    arrowEl.textContent = arrow;
    arrowEl.style.color = arrowColor;
    const pctEl = deltaRow.createSpan({ cls: "health-md-trend-pct" });
    pctEl.textContent = `${Math.abs(delta).toFixed(Math.abs(delta) < 10 ? 1 : 0)}%`;
    pctEl.style.color = arrowColor;
    if (priorAvg != null) {
      const absDelta = currentAvg - priorAvg;
      const deltaStr = `${absDelta >= 0 ? "+" : "\u2212"}${formatValue2(Math.abs(absDelta), meta)} ${meta.unit === "h" ? "" : meta.unit}`.trim();
      const absEl = deltaRow.createSpan({ cls: "health-md-trend-abs" });
      absEl.textContent = deltaStr;
      absEl.style.color = theme.muted;
    }
    const narr = card.createDiv({ cls: "health-md-trend-narrative" });
    narr.textContent = priorVals.length ? narrative(meta, delta, currentWindow + priorWindow) : `Your ${meta.label.toLowerCase()}: ${formatValue2(currentAvg, meta)} ${meta.unit === "h" ? "" : meta.unit}`.trim();
    narr.style.color = theme.muted;
    const spark = buildSparkline2(currentVals, priorVals, meta.color, theme.isDark);
    if (spark) {
      const wrap = card.createDiv({ cls: "health-md-summary-spark" });
      appendSvgFromMarkup(wrap, spark);
    }
    if (currentVals.length >= 5) {
      const mean = currentAvg;
      const variance = currentVals.reduce((s, v) => s + (v - mean) ** 2, 0) / currentVals.length;
      const cv = mean !== 0 ? Math.sqrt(variance) / Math.abs(mean) : 0;
      const label = cv < 0.1 ? "Very consistent" : cv < 0.2 ? "Consistent" : cv < 0.35 ? "Variable" : "Irregular";
      const dotColor = cv < 0.1 ? "#30c26a" : cv < 0.2 ? "#9ecb3f" : cv < 0.35 ? "#ffa534" : "#ff3b30";
      const consistency = card.createDiv({ cls: "health-md-trend-consistency" });
      const dot = consistency.createSpan({ cls: "health-md-trend-dot" });
      dot.style.backgroundColor = dotColor;
      const txt = consistency.createSpan();
      txt.textContent = label;
      txt.style.color = theme.muted;
    }
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/activity-rings.ts
  var RING_COLORS = {
    move: "#fa114f",
    exercise: "#92e82a",
    stand: "#1eeaef"
  };
  function activityRingColors(theme) {
    var _a;
    return (_a = theme.colors.activity) != null ? _a : RING_COLORS;
  }
  function extractValues(day) {
    var _a, _b, _c, _d;
    const act = day.activity;
    if (!act) return { move: 0, exercise: 0, stand: 0 };
    const steps = (_a = act.steps) != null ? _a : 0;
    const standProxy = Math.min(12, Math.floor(steps / 1e3));
    return {
      move: (_b = act.activeCalories) != null ? _b : 0,
      exercise: (_c = act.exerciseMinutes) != null ? _c : 0,
      stand: (_d = act.standHours) != null ? _d : standProxy
    };
  }
  function drawRingSet(ctx, cx, cy, outerR, stroke, values, goals, theme, hits, day, label) {
    const ringColors = activityRingColors(theme);
    const rings = [
      { key: "move", color: ringColors.move, value: values.move, goal: goals.move, unit: "CAL" },
      { key: "exercise", color: ringColors.exercise, value: values.exercise, goal: goals.exercise, unit: "MIN" },
      { key: "stand", color: ringColors.stand, value: values.stand, goal: goals.stand, unit: "HR" }
    ];
    const gap = Math.max(2, stroke * 0.18);
    rings.forEach((ring, i) => {
      const r = outerR - i * (stroke + gap);
      if (r < stroke) return;
      const progress = ring.goal > 0 ? ring.value / ring.goal : 0;
      ctx.strokeStyle = hexToRgba(ring.color, theme.isDark ? 0.18 : 0.15);
      ctx.lineWidth = stroke;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.stroke();
      if (progress <= 0) return;
      const startA = -Math.PI / 2;
      const clamped = Math.min(progress, 1);
      const endA = startA + clamped * Math.PI * 2;
      const grad = ctx.createLinearGradient(cx - r, cy, cx + r, cy);
      grad.addColorStop(0, ring.color);
      grad.addColorStop(1, hexToRgba(ring.color, 0.75));
      ctx.strokeStyle = grad;
      ctx.lineWidth = stroke;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.arc(cx, cy, r, startA, endA);
      ctx.stroke();
      if (progress > 1) {
        const excess = Math.min(progress - 1, 1);
        const excessEnd = startA + excess * Math.PI * 2;
        ctx.strokeStyle = hexToRgba(ring.color, 0.55);
        ctx.beginPath();
        ctx.arc(cx, cy, r, startA, excessEnd);
        ctx.stroke();
      }
      hits.add({
        shape: "sector",
        cx,
        cy,
        r0: r - stroke / 2,
        r1: r + stroke / 2,
        a0: 0,
        a1: Math.PI * 2,
        title: `${label} \u2014 ${ring.key.toUpperCase()}`,
        details: [
          { label: "Value", value: `${Math.round(ring.value)} ${ring.unit}` },
          { label: "Goal", value: `${ring.goal} ${ring.unit}` },
          { label: "Progress", value: `${Math.round(progress * 100)}%` }
        ],
        payload: day
      });
    });
  }
  var renderActivityRings = (ctx, data, W, H, config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const days = data.filter((d) => d.activity);
    if (!days.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("No activity data", W / 2, H / 2);
      return;
    }
    const goals = {
      move: Number(config.moveGoal) || 500,
      exercise: Number(config.exerciseGoal) || 30,
      stand: Number(config.standGoal) || 12
    };
    const ringColors = activityRingColors(theme);
    if (days.length === 1) {
      const day = days[0];
      const values = extractValues(day);
      const cx = W / 2;
      const cy = H / 2;
      const outerR = Math.min(W, H) / 2 - 12;
      const stroke = Math.max(10, outerR * 0.14);
      drawRingSet(ctx, cx, cy, outerR, stroke, values, goals, theme, hits, day, formatDate(day.date));
      const innerR = outerR - 3 * (stroke + stroke * 0.18) - stroke;
      const lines = [
        { text: `${Math.round(values.move)}/${goals.move} CAL`, color: ringColors.move },
        { text: `${Math.round(values.exercise)}/${goals.exercise} MIN`, color: ringColors.exercise },
        { text: `${Math.round(values.stand)}/${goals.stand} HR`, color: ringColors.stand }
      ];
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      const lineH = Math.max(12, innerR * 0.42);
      const fontSize = Math.max(9, Math.min(14, innerR * 0.28));
      ctx.font = `600 ${fontSize}px sans-serif`;
      const startY = cy - (lines.length - 1) * lineH / 2;
      lines.forEach((l, i) => {
        ctx.fillStyle = l.color;
        ctx.fillText(l.text, cx, startY + i * lineH);
      });
      renderStatBoxes(statsEl, [
        {
          value: String(Math.round(values.move)),
          label: `Move / ${goals.move}`,
          color: ringColors.move
        },
        {
          value: String(Math.round(values.exercise)),
          label: `Exercise / ${goals.exercise}`,
          color: ringColors.exercise
        },
        {
          value: String(Math.round(values.stand)),
          label: `Stand / ${goals.stand}`,
          color: ringColors.stand
        }
      ]);
      return;
    }
    const canvas = ctx.canvas;
    const n = days.length;
    const cols = Math.min(n, Math.max(3, Math.round(Math.sqrt(n * (W / H)))));
    const rows = Math.ceil(n / cols);
    const gap = 10;
    const cellW = (W - gap * (cols - 1)) / cols;
    const dateLabelH = 16;
    const cellH = cellW + dateLabelH;
    const neededH = rows * cellH + (rows - 1) * gap + 8;
    if (neededH > H) {
      const dpr = activeWindow.devicePixelRatio || 1;
      canvas.width = W * dpr;
      canvas.height = neededH * dpr;
      canvas.style.width = W + "px";
      canvas.style.height = neededH + "px";
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
      ctx.fillStyle = theme.bg;
      ctx.fillRect(0, 0, W, neededH);
    }
    days.forEach((day, idx) => {
      const row = Math.floor(idx / cols);
      const col = idx % cols;
      const x0 = col * (cellW + gap);
      const y0 = row * (cellH + gap);
      const cx = x0 + cellW / 2;
      const cy = y0 + cellW / 2;
      const outerR = cellW / 2 - 4;
      const stroke = Math.max(4, outerR * 0.18);
      const values = extractValues(day);
      drawRingSet(ctx, cx, cy, outerR, stroke, values, goals, theme, hits, day, formatDate(day.date));
      const d = /* @__PURE__ */ new Date(day.date + "T00:00:00");
      const label = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      ctx.fillStyle = theme.muted;
      ctx.font = "10px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(label, cx, y0 + cellW + dateLabelH / 2 + 1);
    });
    const totalMove = days.reduce((s, d) => s + extractValues(d).move, 0);
    const totalEx = days.reduce((s, d) => s + extractValues(d).exercise, 0);
    const closedMove = days.filter((d) => extractValues(d).move >= goals.move).length;
    const closedEx = days.filter((d) => extractValues(d).exercise >= goals.exercise).length;
    const closedStand = days.filter((d) => extractValues(d).stand >= goals.stand).length;
    renderStatBoxes(statsEl, [
      {
        value: `${closedMove}/${days.length}`,
        label: "Move closed",
        color: ringColors.move
      },
      {
        value: `${closedEx}/${days.length}`,
        label: "Exercise closed",
        color: ringColors.exercise
      },
      {
        value: `${closedStand}/${days.length}`,
        label: "Stand closed",
        color: ringColors.stand
      },
      {
        value: Math.round(totalMove).toLocaleString(),
        label: "Total CAL"
      },
      {
        value: String(Math.round(totalEx)),
        label: "Total min"
      }
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/range-chart-core.ts
  function renderRangeChart(ctx, data, W, H, theme, statsEl, hits, spec) {
    var _a, _b, _c, _d, _e, _f;
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const points = data.map((d) => {
      const v = spec.extract(d);
      return v ? { day: d, date: d.date, ...v } : null;
    });
    const present = points.filter((p) => p !== null);
    if (!present.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(`No ${spec.label.toLowerCase()} data`, W / 2, H / 2);
      return;
    }
    const padL = (_a = spec.padL) != null ? _a : 36;
    const padR = 16, padT = 14, padB = 24;
    const plotW2 = W - padL - padR;
    const plotH = H - padT - padB;
    const observedMin = Math.min(...present.map((p) => p.min));
    const observedMax = Math.max(...present.map((p) => p.max));
    const { yMin, yMax, gridStep } = spec.yAxis({ min: observedMin, max: observedMax });
    const yRange = yMax - yMin || 1;
    const n = points.length;
    const xFor = (i) => padL + (n === 1 ? plotW2 / 2 : i / (n - 1) * plotW2);
    const yFor = (v) => padT + plotH - (v - yMin) / yRange * plotH;
    if (spec.warn) {
      ctx.fillStyle = hexToRgba(spec.warn.color, theme.isDark ? 0.12 : 0.08);
      if (spec.warn.lo != null) {
        const yThreshold = yFor(spec.warn.lo);
        ctx.fillRect(padL, yThreshold, plotW2, padT + plotH - yThreshold);
      }
      if (spec.warn.hi != null) {
        const yThreshold = yFor(spec.warn.hi);
        ctx.fillRect(padL, padT, plotW2, yThreshold - padT);
      }
    }
    ctx.strokeStyle = hexToRgba(theme.fg, 0.07);
    ctx.lineWidth = 1;
    ctx.fillStyle = theme.muted;
    ctx.font = "9px sans-serif";
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";
    const startGrid = Math.ceil(yMin / gridStep) * gridStep;
    for (let v = startGrid; v <= yMax; v += gridStep) {
      const y = yFor(v);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.fillText(spec.formatAxisLabel(v), padL - 4, y);
    }
    if (spec.warn) {
      const thresholdV = (_b = spec.warn.lo) != null ? _b : spec.warn.hi;
      const y = yFor(thresholdV);
      ctx.save();
      ctx.strokeStyle = hexToRgba(spec.warn.color, 0.55);
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 3]);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.restore();
      const labelY = Math.max(padT + 10, Math.min(padT + plotH - 6, y));
      ctx.fillStyle = spec.warn.color;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText(spec.warn.note, padL + 4, labelY);
    }
    if (spec.overlays) {
      spec.overlays({ ctx, data, yFor, yMin, yMax, padL, padR, W });
    }
    const capW = Math.max(4, Math.min(10, plotW2 / Math.max(1, n) * 0.45));
    const capRadius = capW / 2;
    const avgDotInnerLight = (_c = spec.avgDotInnerLightFill) != null ? _c : "#000";
    points.forEach((p, i) => {
      if (!p) return;
      const x = xFor(i);
      const yTop = yFor(p.max);
      const yBot = yFor(p.min);
      const h = Math.max(capW, yBot - yTop);
      const grad = ctx.createLinearGradient(0, yTop, 0, yTop + h);
      grad.addColorStop(0, hexToRgba(spec.capsuleColor, 1));
      grad.addColorStop(1, hexToRgba(spec.capsuleColor, 0.55));
      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.roundRect(x - capW / 2, yTop, capW, h, capRadius);
      ctx.fill();
      const yAvg = yFor(p.avg);
      ctx.fillStyle = theme.isDark ? "#fff" : avgDotInnerLight;
      ctx.beginPath();
      ctx.arc(x, yAvg, Math.max(2, capW * 0.38), 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = spec.capsuleColor;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(x, yAvg, Math.max(2, capW * 0.38), 0, Math.PI * 2);
      ctx.stroke();
      hits.add({
        shape: "rect",
        x: x - capW,
        y: yTop - 4,
        w: capW * 2,
        h: h + 8,
        title: formatDate(p.date),
        details: [
          { label: "Avg", value: `${spec.formatValue(p.avg)} ${spec.unit}` },
          { label: "Min", value: `${spec.formatValue(p.min)} ${spec.unit}` },
          { label: "Max", value: `${spec.formatValue(p.max)} ${spec.unit}` }
        ],
        payload: p.day
      });
    });
    const labelStep = Math.max(1, Math.floor(n / 6));
    ctx.fillStyle = theme.muted;
    ctx.font = "9px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    for (let i = 0; i < n; i++) {
      if (i % labelStep !== 0 && i !== n - 1) continue;
      const iso = (_f = (_d = points[i]) == null ? void 0 : _d.date) != null ? _f : (_e = data[i]) == null ? void 0 : _e.date;
      if (!iso) continue;
      const d = /* @__PURE__ */ new Date(iso + "T00:00:00");
      const label = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      ctx.fillText(label, xFor(i), H - padB + 6);
    }
    const overallMin = Math.min(...present.map((p) => p.min));
    const overallMax = Math.max(...present.map((p) => p.max));
    const overallAvg = present.reduce((s, p) => s + p.avg, 0) / present.length;
    renderStatBoxes(statsEl, [
      {
        value: spec.formatValue(overallMin),
        label: "Lowest",
        color: spec.stats.lowColor
      },
      {
        value: spec.formatValue(overallAvg),
        label: `${spec.label} avg`,
        color: spec.stats.avgColor
      },
      {
        value: spec.formatValue(overallMax),
        label: "Highest",
        color: spec.stats.highColor
      }
    ]);
  }

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/heart-range.ts
  var CAP_COLOR = "#ff3b30";
  var RESTING_COLOR = "#4488ff";
  function extractForMetric(day, metric) {
    if (!day.heart) return null;
    if (metric === "resting") {
      const v = day.heart.restingHeartRate;
      if (v == null || v <= 0) return null;
      return { min: v, max: v, avg: v };
    }
    if (metric === "walking") {
      const v = day.heart.walkingHeartRateAverage;
      if (v == null || v <= 0) return null;
      return { min: v, max: v, avg: v };
    }
    const min = day.heart.heartRateMin;
    const max = day.heart.heartRateMax;
    const avg3 = day.heart.averageHeartRate;
    if (avg3 == null || avg3 <= 0) return null;
    return { min: min > 0 ? min : avg3, max: max > 0 ? max : avg3, avg: avg3 };
  }
  function labelFor(m) {
    if (m === "resting") return "Resting HR";
    if (m === "walking") return "Walking HR";
    return "Heart Rate";
  }
  function restingOverlay({ ctx, data, yFor, yMin, yMax, padL, padR, W }) {
    const vals = data.map((d) => {
      var _a;
      return (_a = d.heart) == null ? void 0 : _a.restingHeartRate;
    }).filter((v) => v != null && v > 0);
    if (!vals.length) return;
    const rest = vals.reduce((s, x) => s + x, 0) / vals.length;
    if (rest < yMin || rest > yMax) return;
    const y = yFor(rest);
    ctx.save();
    ctx.strokeStyle = hexToRgba(RESTING_COLOR, 0.55);
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(padL, y);
    ctx.lineTo(W - padR, y);
    ctx.stroke();
    ctx.restore();
    const labelY = Math.max(yFor(yMax) + 10, Math.min(yFor(yMin) - 6, y));
    ctx.fillStyle = RESTING_COLOR;
    ctx.font = "9px sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText(`resting ~${Math.round(rest)}`, padL + 4, labelY);
  }
  var renderHeartRange = (ctx, data, W, H, config, theme, statsEl, hits) => {
    const metric = config.metric || "heart-rate";
    const spec = {
      label: labelFor(metric),
      unit: "bpm",
      capsuleColor: CAP_COLOR,
      padL: 36,
      avgDotInnerLightFill: "#1a0000",
      extract: (d) => extractForMetric(d, metric),
      yAxis: ({ min, max }) => {
        const yMin = Math.max(0, Math.floor((min - 20) / 10) * 10);
        const yMax = Math.ceil((max + 20) / 10) * 10;
        const range = yMax - yMin || 1;
        return { yMin, yMax, gridStep: range > 120 ? 40 : 20 };
      },
      formatAxisLabel: (v) => String(v),
      formatValue: (v) => String(Math.round(v)),
      stats: { lowColor: RESTING_COLOR, avgColor: CAP_COLOR, highColor: CAP_COLOR },
      overlays: metric === "heart-rate" ? restingOverlay : void 0
    };
    renderRangeChart(ctx, data, W, H, theme, statsEl, hits, spec);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/bar-chart.ts
  var METRICS3 = {
    steps: {
      label: "Steps",
      unit: "steps",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.activity) == null ? void 0 : _a.steps) != null ? _b : 0;
      },
      formatTotal: (sum) => sum.toLocaleString(),
      formatValue: (v) => Math.round(v).toLocaleString(),
      aggregate: "sum"
    },
    activeCalories: {
      label: "Active Energy",
      unit: "CAL",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.activity) == null ? void 0 : _a.activeCalories) != null ? _b : 0;
      },
      formatTotal: (sum) => Math.round(sum).toLocaleString(),
      formatValue: (v) => `${Math.round(v)}`,
      aggregate: "sum"
    },
    exerciseMinutes: {
      label: "Exercise",
      unit: "min",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.activity) == null ? void 0 : _a.exerciseMinutes) != null ? _b : 0;
      },
      formatTotal: (sum) => `${Math.round(sum)}`,
      formatValue: (v) => `${Math.round(v)}`,
      aggregate: "sum"
    },
    distance: {
      label: "Distance",
      unit: "km",
      color: (t) => t.colors.secondary,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.activity) == null ? void 0 : _a.walkingRunningDistanceKm) != null ? _b : 0;
      },
      formatTotal: (sum) => sum.toFixed(1),
      formatValue: (v) => v.toFixed(2),
      aggregate: "sum"
    },
    sleepHours: {
      label: "Sleep",
      unit: "h",
      color: (t) => t.colors.sleep.rem,
      extract: (d) => {
        var _a, _b;
        return ((_b = (_a = d.sleep) == null ? void 0 : _a.totalDuration) != null ? _b : 0) / 3600;
      },
      formatTotal: (sum) => sum.toFixed(1),
      formatValue: (v) => {
        const h = Math.floor(v);
        const m = Math.round((v - h) * 60);
        return `${h}h ${m}m`;
      },
      aggregate: "avg"
    },
    flightsClimbed: {
      label: "Flights Climbed",
      unit: "flights",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.activity) == null ? void 0 : _a.flightsClimbed) != null ? _b : 0;
      },
      formatTotal: (sum) => `${Math.round(sum)}`,
      formatValue: (v) => `${Math.round(v)}`,
      aggregate: "sum"
    }
  };
  var WEEKDAY_INITIAL = ["S", "M", "T", "W", "T", "F", "S"];
  var renderBarChart = (ctx, data, W, H, config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const metricId = config.metric || "steps";
    const meta = METRICS3[metricId];
    if (!meta) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(`Unknown metric: ${metricId}`, W / 2, H / 2);
      return;
    }
    const days = data;
    if (!days.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("No data in range", W / 2, H / 2);
      return;
    }
    const values = days.map((d) => meta.extract(d));
    const n = values.length;
    const max = Math.max(...values, 0);
    const nonZero = values.filter((v) => v > 0);
    const total = values.reduce((s, v) => s + v, 0);
    const average2 = nonZero.length ? total / nonZero.length : 0;
    const goal = config.goal != null ? Number(config.goal) : void 0;
    const showAverage = config.showAverage === void 0 || config.showAverage === "true" || config.showAverage === 1 || config.showAverage === "1";
    const chartEffectiveMax = goal && goal > max ? goal : max;
    const denom = chartEffectiveMax > 0 ? chartEffectiveMax : 1;
    const kpiH = 46;
    const axisH = 18;
    const padT = 8;
    const padB = axisH + 8;
    const padL = 16;
    const padR = 36;
    const plotTop = padT + kpiH;
    const plotH = H - plotTop - padB;
    const headline = meta.aggregate === "sum" ? meta.formatTotal(total) : meta.formatValue(average2);
    const subtitle = `${formatDate(days[0].date)} \u2013 ${formatDate(days[n - 1].date)}`;
    ctx.textAlign = "left";
    ctx.textBaseline = "alphabetic";
    ctx.fillStyle = theme.fg;
    ctx.font = "600 22px sans-serif";
    const headlineMetrics = ctx.measureText(headline);
    ctx.fillText(headline, padL, padT + 22);
    ctx.fillStyle = theme.muted;
    ctx.font = "11px sans-serif";
    ctx.fillText(` ${meta.unit}`, padL + headlineMetrics.width + 2, padT + 22);
    ctx.fillText(subtitle, padL, padT + 40);
    const accent = meta.color(theme);
    if (chartEffectiveMax > 0) {
      ctx.fillStyle = theme.muted;
      ctx.font = "10px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "top";
      ctx.fillText(meta.formatValue(chartEffectiveMax), W - 4, plotTop);
    }
    if (showAverage && average2 > 0 && chartEffectiveMax > 0) {
      const y = plotTop + plotH - average2 / denom * plotH;
      ctx.save();
      ctx.strokeStyle = hexToRgba(theme.fg, 0.4);
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.restore();
      const labelY = Math.max(plotTop + 10, Math.min(plotTop + plotH - 6, y));
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      ctx.fillText(`avg ${meta.formatValue(average2)}`, W - padR - 4, labelY);
    }
    if (goal && chartEffectiveMax > 0) {
      const y = plotTop + plotH - goal / denom * plotH;
      ctx.save();
      ctx.strokeStyle = hexToRgba(accent, 0.8);
      ctx.lineWidth = 1;
      ctx.setLineDash([2, 3]);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.restore();
      const labelY = Math.max(plotTop + 10, Math.min(plotTop + plotH - 6, y));
      ctx.fillStyle = accent;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText(`goal ${meta.formatValue(goal)}`, padL + 2, labelY);
    }
    const chartW = W - padL - padR;
    const slot = chartW / n;
    const barW = Math.max(3, Math.min(slot * 0.72, 28));
    const cornerR = Math.min(barW / 2, 6);
    const highlightIdx = n - 1;
    for (let i = 0; i < n; i++) {
      const v = values[i];
      const x = padL + i * slot + (slot - barW) / 2;
      const isHighlight = i === highlightIdx;
      const h = v / denom * plotH;
      const y = plotTop + plotH - h;
      if (h <= 0.5) {
        ctx.fillStyle = hexToRgba(accent, 0.12);
        ctx.beginPath();
        ctx.roundRect(x, plotTop + plotH - 2, barW, 2, 1);
        ctx.fill();
      } else {
        ctx.fillStyle = isHighlight ? accent : hexToRgba(accent, 0.35);
        ctx.beginPath();
        ctx.roundRect(x, y, barW, h, [cornerR, cornerR, 0, 0]);
        ctx.fill();
      }
      hits.add({
        shape: "rect",
        x: padL + i * slot,
        y: plotTop,
        w: slot,
        h: plotH + axisH,
        title: formatDate(days[i].date),
        details: [
          { label: meta.label, value: `${meta.formatValue(v)} ${meta.unit}` }
        ],
        payload: days[i]
      });
    }
    ctx.fillStyle = theme.muted;
    ctx.font = "10px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    if (n <= 7) {
      for (let i = 0; i < n; i++) {
        const d = /* @__PURE__ */ new Date(days[i].date + "T00:00:00");
        const ch = WEEKDAY_INITIAL[d.getDay()];
        const cx = padL + i * slot + slot / 2;
        ctx.fillStyle = i === highlightIdx ? theme.fg : theme.muted;
        ctx.fillText(ch, cx, plotTop + plotH + 4);
      }
    } else {
      const maxLabels = Math.max(2, Math.floor(plotW / 72));
      const labelStep = Math.max(1, Math.ceil(n / maxLabels));
      for (let i = 0; i < n; i++) {
        if (i % labelStep !== 0 && i !== n - 1) continue;
        const d = /* @__PURE__ */ new Date(days[i].date + "T00:00:00");
        const label = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
        const cx = padL + i * slot + slot / 2;
        ctx.fillStyle = i === highlightIdx ? theme.fg : theme.muted;
        ctx.fillText(label, cx, plotTop + plotH + 4);
      }
    }
    const bestIdx = values.reduce(
      (best2, v, i) => v > values[best2] ? i : best2,
      0
    );
    const best = values[bestIdx];
    const bestLabel = (/* @__PURE__ */ new Date(days[bestIdx].date + "T00:00:00")).toLocaleDateString(
      "en-US",
      { month: "short", day: "numeric" }
    );
    renderStatBoxes(statsEl, [
      {
        value: meta.aggregate === "sum" ? meta.formatTotal(total) : meta.formatValue(total),
        label: `Total ${meta.unit}`
      },
      { value: meta.formatValue(average2), label: "Daily avg" },
      { value: meta.formatValue(best), label: `Best (${bestLabel})` }
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/sleep-schedule.ts
  var DAY_MS = 864e5;
  function parseWindow(str) {
    const clock = parseClockTime(str);
    if (!clock) return { h: 0, m: 0 };
    return { h: clock.h, m: clock.m };
  }
  function parseClockTime(raw) {
    var _a, _b;
    const value = raw == null ? void 0 : raw.trim();
    if (!value) return null;
    let m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(value);
    if (m) {
      const h = Number(m[1]);
      const min = Number(m[2]);
      const sec = Number((_a = m[3]) != null ? _a : 0);
      if (h <= 23 && min <= 59 && sec <= 59) return { h, m: min, s: sec };
      return null;
    }
    m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap])\.?m\.?$/i.exec(value);
    if (m) {
      let h = Number(m[1]);
      const min = Number(m[2]);
      const sec = Number((_b = m[3]) != null ? _b : 0);
      if (h < 1 || h > 12 || min > 59 || sec > 59) return null;
      const meridiem = m[4].toLowerCase();
      if (meridiem === "p" && h !== 12) h += 12;
      if (meridiem === "a" && h === 12) h = 0;
      return { h, m: min, s: sec };
    }
    return null;
  }
  function clockMsOnDate(dateIso, clock) {
    return (/* @__PURE__ */ new Date(
      `${dateIso}T${String(clock.h).padStart(2, "0")}:${String(clock.m).padStart(2, "0")}:${String(clock.s).padStart(2, "0")}`
    )).getTime();
  }
  function parseAbsoluteMs(raw) {
    if (!(raw == null ? void 0 : raw.trim())) return NaN;
    return Date.parse(raw.trim());
  }
  function resolveExplicitBedWake(night, sleep) {
    var _a, _b, _c, _d;
    const bedRaw = (_b = (_a = sleep.bedtimeISO) != null ? _a : sleep.sessionStart) != null ? _b : sleep.bedtime;
    const wakeRaw = (_d = (_c = sleep.wakeTimeISO) != null ? _c : sleep.sessionEnd) != null ? _d : sleep.wakeTime;
    if (!bedRaw || !wakeRaw) return null;
    const bedClock = parseClockTime(bedRaw);
    const wakeClock = parseClockTime(wakeRaw);
    let bedMs = bedClock ? clockMsOnDate(night.date, bedClock) : parseAbsoluteMs(bedRaw);
    let wakeMs = wakeClock ? clockMsOnDate(night.date, wakeClock) : parseAbsoluteMs(wakeRaw);
    if (!isFinite(bedMs) || !isFinite(wakeMs)) return null;
    if (wakeMs <= bedMs && (bedClock || wakeClock)) wakeMs += DAY_MS;
    if (wakeMs <= bedMs) return null;
    return { bedMs, wakeMs };
  }
  function resolveStageBedWake(sleep) {
    var _a;
    const stages = (_a = sleep.sleepStages) != null ? _a : [];
    let bedMs = Infinity;
    let wakeMs = -Infinity;
    for (const stage of stages) {
      const startMs = Date.parse(stage.startDate);
      const endMs = Date.parse(stage.endDate);
      if (isFinite(startMs) && startMs < bedMs) bedMs = startMs;
      if (isFinite(endMs) && endMs > wakeMs) wakeMs = endMs;
    }
    if (!isFinite(bedMs) || !isFinite(wakeMs) || wakeMs <= bedMs) return null;
    return { bedMs, wakeMs };
  }
  function resolveBedWake(night) {
    var _a;
    const sleep = night.sleep;
    if (!sleep) return null;
    return (_a = resolveExplicitBedWake(night, sleep)) != null ? _a : resolveStageBedWake(sleep);
  }
  function formatHour(ms) {
    return new Date(ms).toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit"
    });
  }
  function hourLabel(h) {
    const hr = (h % 24 + 24) % 24;
    if (hr === 0) return "12A";
    if (hr === 12) return "12P";
    if (hr < 12) return `${hr}A`;
    return `${hr - 12}P`;
  }
  function localDateIso(ms) {
    const d = new Date(ms);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }
  function addDaysIso(dateIso, days) {
    const d = /* @__PURE__ */ new Date(`${dateIso}T00:00:00`);
    d.setDate(d.getDate() + days);
    return localDateIso(d.getTime());
  }
  var renderSleepSchedule = (ctx, data, W, H, config, theme, statsEl, hits) => {
    var _a, _b, _c;
    const canvas = ctx.canvas;
    const sleepGoalHours = Number(config.sleepGoal) || 8;
    const windowStart = parseWindow(String(config.windowStart || "18:00"));
    const windowEnd = parseWindow(String(config.windowEnd || "10:00"));
    const nights = [];
    for (const d of data) {
      if (!d.sleep) continue;
      const stageCount = (_b = (_a = d.sleep.sleepStages) == null ? void 0 : _a.length) != null ? _b : 0;
      const totalDuration = (_c = d.sleep.totalDuration) != null ? _c : 0;
      if (!(stageCount > 0 || totalDuration > 0)) continue;
      const bw = resolveBedWake(d);
      if (!bw) continue;
      nights.push({
        date: d.date,
        day: d,
        bedMs: bw.bedMs,
        wakeMs: bw.wakeMs,
        totalSeconds: totalDuration || (bw.wakeMs - bw.bedMs) / 1e3
      });
    }
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    if (!nights.length) {
      ctx.fillStyle = theme.muted;
      ctx.textAlign = "center";
      ctx.font = "12px sans-serif";
      ctx.fillText("No sleep schedule data", W / 2, H / 2 - 8);
      ctx.font = "10px sans-serif";
      ctx.fillText("Requires bedtime/wake or stage timestamps", W / 2, H / 2 + 10);
      return;
    }
    const rowH = 26;
    const rowGap = 6;
    const padT = 10;
    const axisH = 34;
    const gutterW = 104;
    const rightPad = 16;
    const barAreaX = gutterW;
    const barAreaW = W - gutterW - rightPad;
    const neededH = padT + nights.length * (rowH + rowGap) + axisH + 8;
    if (neededH !== H) {
      const dpr = activeWindow.devicePixelRatio || 1;
      canvas.width = W * dpr;
      canvas.height = neededH * dpr;
      canvas.style.width = W + "px";
      canvas.style.height = neededH + "px";
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
      ctx.fillStyle = theme.bg;
      ctx.fillRect(0, 0, W, neededH);
    }
    function windowBoundsFor(dateIso) {
      const startMs = (/* @__PURE__ */ new Date(`${dateIso}T${String(windowStart.h).padStart(2, "0")}:${String(windowStart.m).padStart(2, "0")}:00`)).getTime();
      const base = (/* @__PURE__ */ new Date(`${dateIso}T00:00:00`)).getTime();
      let endMs = base + 864e5 + windowEnd.h * 36e5 + windowEnd.m * 6e4;
      if (endMs <= startMs) endMs += 864e5;
      return { startMs, endMs };
    }
    function windowBoundsForNight(night) {
      const bedDate = localDateIso(night.bedMs);
      const wakeDate = localDateIso(night.wakeMs);
      const candidates = Array.from(/* @__PURE__ */ new Set([
        addDaysIso(night.date, -1),
        night.date,
        addDaysIso(night.date, 1),
        addDaysIso(bedDate, -1),
        bedDate,
        addDaysIso(bedDate, 1),
        addDaysIso(wakeDate, -1),
        wakeDate
      ]));
      let best = windowBoundsFor(night.date);
      let bestOverlap = -1;
      let bestDistance = Infinity;
      for (const dateIso of candidates) {
        const bounds = windowBoundsFor(dateIso);
        const overlap = Math.max(
          0,
          Math.min(night.wakeMs, bounds.endMs) - Math.max(night.bedMs, bounds.startMs)
        );
        const distance = Math.abs(night.bedMs - bounds.startMs);
        if (overlap > bestOverlap || overlap === bestOverlap && distance < bestDistance) {
          best = bounds;
          bestOverlap = overlap;
          bestDistance = distance;
        }
      }
      return best;
    }
    const nightBounds = nights.map(windowBoundsForNight);
    const sampleBounds = nightBounds[0];
    const windowSpan = sampleBounds.endMs - sampleBounds.startMs;
    const windowHours = windowSpan / 36e5;
    const plotTop = padT;
    const plotH = nights.length * (rowH + rowGap) - rowGap;
    const bgGrad = ctx.createLinearGradient(barAreaX, 0, barAreaX + barAreaW, 0);
    const cSunset = theme.isDark ? "#3a1a3a" : "#f5dccc";
    const cNight = theme.isDark ? "#0b0b22" : "#d6dbe8";
    const cSunrise = theme.isDark ? "#3a2a14" : "#fee7c8";
    bgGrad.addColorStop(0, cSunset);
    bgGrad.addColorStop(0.45, cNight);
    bgGrad.addColorStop(0.65, cNight);
    bgGrad.addColorStop(1, cSunrise);
    ctx.fillStyle = bgGrad;
    ctx.beginPath();
    ctx.roundRect(barAreaX, plotTop, barAreaW, plotH, 8);
    ctx.fill();
    ctx.strokeStyle = hexToRgba(theme.fg, 0.08);
    ctx.lineWidth = 1;
    const startHour = windowStart.h;
    const numTicks = Math.max(2, Math.round(windowHours / 2));
    for (let k = 0; k <= numTicks; k++) {
      const frac = k / numTicks;
      const x = barAreaX + frac * barAreaW;
      ctx.beginPath();
      ctx.moveTo(x, plotTop);
      ctx.lineTo(x, plotTop + plotH);
      ctx.stroke();
      const h = startHour + frac * windowHours;
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "top";
      ctx.fillText(hourLabel(h), x, plotTop + plotH + 4);
    }
    const meanBedOffset = nights.reduce((s, nn, i) => {
      const wb = nightBounds[i];
      return s + (nn.bedMs - wb.startMs);
    }, 0) / nights.length;
    const goalSpan = sleepGoalHours * 36e5;
    const goalStartFrac = meanBedOffset / windowSpan;
    const goalEndFrac = (meanBedOffset + goalSpan) / windowSpan;
    if (goalEndFrac > 0 && goalStartFrac < 1) {
      const gx0 = barAreaX + Math.max(0, goalStartFrac) * barAreaW;
      const gx1 = barAreaX + Math.min(1, goalEndFrac) * barAreaW;
      ctx.save();
      ctx.strokeStyle = hexToRgba(theme.colors.sleep.rem, 0.8);
      ctx.lineWidth = 1;
      ctx.setLineDash([3, 3]);
      ctx.beginPath();
      ctx.moveTo(gx0, plotTop + plotH + 18);
      ctx.lineTo(gx1, plotTop + plotH + 18);
      ctx.stroke();
      ctx.restore();
      ctx.fillStyle = theme.colors.sleep.rem;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "top";
      ctx.fillText(`goal ${sleepGoalHours}h`, (gx0 + gx1) / 2, plotTop + plotH + 22);
    }
    nights.forEach((n, i) => {
      const wb = nightBounds[i];
      const y = padT + i * (rowH + rowGap);
      const d = /* @__PURE__ */ new Date(n.date + "T00:00:00");
      const weekday = d.toLocaleDateString("en-US", { weekday: "short" });
      const datepart = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      ctx.fillStyle = theme.fg;
      ctx.font = "600 11px sans-serif";
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText(weekday, 10, y + rowH / 2 - 6);
      ctx.fillStyle = theme.muted;
      ctx.font = "10px sans-serif";
      ctx.fillText(datepart, 10, y + rowH / 2 + 7);
      const bedFrac = Math.max(0, Math.min(1, (n.bedMs - wb.startMs) / windowSpan));
      const wakeFrac = Math.max(0, Math.min(1, (n.wakeMs - wb.startMs) / windowSpan));
      if (wakeFrac <= bedFrac) return;
      const bx = barAreaX + bedFrac * barAreaW;
      const bw2 = (wakeFrac - bedFrac) * barAreaW;
      const sleptHours = n.totalSeconds / 3600;
      let barColor = theme.colors.sleep.core;
      if (sleptHours >= sleepGoalHours * 0.95 && sleptHours <= sleepGoalHours * 1.15) {
        barColor = theme.colors.sleep.rem;
      } else if (sleptHours < sleepGoalHours * 0.85) {
        barColor = theme.colors.sleep.awake;
      } else {
        barColor = theme.colors.sleep.deep;
      }
      ctx.fillStyle = hexToRgba(barColor, 0.45);
      ctx.beginPath();
      ctx.roundRect(bx, y + 3, bw2, rowH - 6, 4);
      ctx.fill();
      const bedWindowSec = (n.wakeMs - n.bedMs) / 1e3;
      const asleepFrac = bedWindowSec > 0 ? Math.min(1, n.totalSeconds / bedWindowSec) : 1;
      if (asleepFrac < 1 && asleepFrac > 0) {
        const innerW = bw2 * asleepFrac;
        ctx.fillStyle = barColor;
        ctx.beginPath();
        ctx.roundRect(bx, y + 6, innerW, rowH - 12, 3);
        ctx.fill();
      } else {
        ctx.fillStyle = barColor;
        ctx.beginPath();
        ctx.roundRect(bx, y + 6, bw2, rowH - 12, 3);
        ctx.fill();
      }
      hits.add({
        shape: "rect",
        x: bx,
        y,
        w: bw2,
        h: rowH,
        title: formatDate(n.date),
        details: [
          { label: "Bedtime", value: formatHour(n.bedMs) },
          { label: "Wake", value: formatHour(n.wakeMs) },
          { label: "Total sleep", value: formatDuration(n.totalSeconds) },
          { label: "Goal", value: `${sleepGoalHours}h` }
        ],
        payload: n.day
      });
    });
    const bedOffsets = nights.map((n, i) => {
      const wb = nightBounds[i];
      return (n.bedMs - wb.startMs) / 36e5;
    });
    const wakeOffsets = nights.map((n, i) => {
      const wb = nightBounds[i];
      return (n.wakeMs - wb.startMs) / 36e5;
    });
    const meanBedH = bedOffsets.reduce((s, v) => s + v, 0) / bedOffsets.length;
    const meanWakeH = wakeOffsets.reduce((s, v) => s + v, 0) / wakeOffsets.length;
    const variance = bedOffsets.reduce((s, v) => s + (v - meanBedH) ** 2, 0) / bedOffsets.length;
    const stdev = Math.sqrt(variance);
    function offsetToHourStr(offsetH) {
      const abs = new Date(nightBounds[0].startMs + offsetH * 36e5);
      return abs.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
    }
    const consistencyLabel = stdev < 0.5 ? "Very consistent" : stdev < 1 ? "Consistent" : stdev < 2 ? "Variable" : "Irregular";
    renderStatBoxes(statsEl, [
      { value: offsetToHourStr(meanBedH), label: "Avg bedtime" },
      { value: offsetToHourStr(meanWakeH), label: "Avg wake" },
      { value: consistencyLabel, label: `\xB1${stdev.toFixed(1)}h stdev` }
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/weekday-average.ts
  var METRICS4 = {
    steps: {
      label: "Steps",
      unit: "steps",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return ((_b = (_a = d.activity) == null ? void 0 : _a.steps) != null ? _b : 0) > 0 ? d.activity.steps : null;
      },
      format: (v) => Math.round(v).toLocaleString()
    },
    activeCalories: {
      label: "Active Calories",
      unit: "CAL",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return ((_b = (_a = d.activity) == null ? void 0 : _a.activeCalories) != null ? _b : 0) > 0 ? d.activity.activeCalories : null;
      },
      format: (v) => `${Math.round(v)}`
    },
    exerciseMinutes: {
      label: "Exercise",
      unit: "min",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return ((_b = (_a = d.activity) == null ? void 0 : _a.exerciseMinutes) != null ? _b : 0) > 0 ? d.activity.exerciseMinutes : null;
      },
      format: (v) => `${Math.round(v)}`
    },
    sleepHours: {
      label: "Sleep",
      unit: "h",
      color: (t) => t.colors.sleep.rem,
      extract: (d) => {
        var _a;
        const v = (_a = d.sleep) == null ? void 0 : _a.totalDuration;
        return v != null && v > 0 ? v / 3600 : null;
      },
      format: (v) => {
        const h = Math.floor(v);
        const m = Math.round((v - h) * 60);
        return `${h}h ${m}m`;
      }
    },
    heartRate: {
      label: "Avg HR",
      unit: "bpm",
      color: (t) => t.colors.heart,
      extract: (d) => {
        var _a;
        const v = (_a = d.heart) == null ? void 0 : _a.averageHeartRate;
        return v != null && v > 0 ? v : null;
      },
      format: (v) => `${Math.round(v)}`
    },
    hrv: {
      label: "HRV",
      unit: "ms",
      color: (t) => t.colors.secondary,
      extract: (d) => {
        var _a, _b;
        if (((_a = d.heart) == null ? void 0 : _a.hrv) != null) return d.heart.hrv;
        const s = (_b = d.heart) == null ? void 0 : _b.hrvSamples;
        if (s && s.length) return s.reduce((acc, x) => acc + x.value, 0) / s.length;
        return null;
      },
      format: (v) => v.toFixed(1)
    }
  };
  var renderWeekdayAverage = (ctx, data, W, H, config, theme, statsEl, hits) => {
    var _a, _b;
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const metricId = config.metric || "steps";
    const meta = METRICS4[metricId];
    if (!meta) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(`Unknown metric: ${metricId}`, W / 2, H / 2);
      return;
    }
    const weekStart = String(config.weekStart || "monday").toLowerCase() === "sunday" ? "sunday" : "monday";
    if (data.length < 7) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("Weekday averages need at least 7 days of data.", W / 2, H / 2);
      return;
    }
    const buckets = Array.from(
      { length: 7 },
      () => ({ values: [], dates: [] })
    );
    data.forEach((day) => {
      const v = meta.extract(day);
      if (v == null) return;
      const dow = (/* @__PURE__ */ new Date(day.date + "T00:00:00")).getDay();
      buckets[dow].values.push(v);
      buckets[dow].dates.push(day.date);
    });
    const orderIdx = weekStart === "sunday" ? [0, 1, 2, 3, 4, 5, 6] : [1, 2, 3, 4, 5, 6, 0];
    const initials = orderIdx.map((d) => ["S", "M", "T", "W", "T", "F", "S"][d]);
    const avgs = orderIdx.map((dow) => {
      const b = buckets[dow];
      return b.values.length ? b.values.reduce((s, v) => s + v, 0) / b.values.length : null;
    });
    const counts = orderIdx.map((dow) => buckets[dow].values.length);
    const hasAny = avgs.some((a) => a != null);
    if (!hasAny) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(`No ${meta.label.toLowerCase()} data`, W / 2, H / 2);
      return;
    }
    const maxAvg = Math.max(...avgs.map((a) => a != null ? a : 0));
    const allValues = avgs.filter((a) => a != null);
    const overallMean = allValues.reduce((s, v) => s + v, 0) / allValues.length;
    const totalSamples = counts.reduce((s, c) => s + c, 0);
    const weeksApprox = Math.max(1, Math.round(totalSamples / 7));
    const padT = 14;
    const kpiH = 40;
    const axisH = 18;
    const padL = 16;
    const padR = 16;
    const valueLabelH = 14;
    const plotTop = padT + kpiH;
    const plotBottom = H - axisH - 6;
    const plotH = plotBottom - plotTop - valueLabelH;
    ctx.textAlign = "left";
    ctx.textBaseline = "alphabetic";
    ctx.fillStyle = theme.fg;
    ctx.font = "600 20px sans-serif";
    const headlineText = `${meta.format(overallMean)} ${meta.unit}`;
    ctx.fillText(headlineText, padL, padT + 20);
    ctx.fillStyle = theme.muted;
    ctx.font = "11px sans-serif";
    ctx.fillText(`Avg ${meta.label.toLowerCase()} across ${weeksApprox} week${weeksApprox === 1 ? "" : "s"}`, padL, padT + 38);
    const color = meta.color(theme);
    if (overallMean > 0 && maxAvg > 0) {
      const y = plotTop + valueLabelH + plotH - overallMean / maxAvg * plotH;
      ctx.save();
      ctx.strokeStyle = hexToRgba(theme.fg, 0.45);
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.restore();
      const labelY = Math.max(plotTop + valueLabelH + 10, Math.min(plotBottom - 8, y));
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      ctx.fillText(`mean ${meta.format(overallMean)}`, W - padR - 2, labelY);
    }
    let maxIdx = 0;
    for (let i = 1; i < 7; i++) {
      if (((_a = avgs[i]) != null ? _a : 0) > ((_b = avgs[maxIdx]) != null ? _b : 0)) maxIdx = i;
    }
    const chartW = W - padL - padR;
    const slot = chartW / 7;
    const barW = Math.min(46, slot * 0.7);
    const cornerR = Math.min(barW / 2, 8);
    for (let i = 0; i < 7; i++) {
      const v = avgs[i];
      const x = padL + i * slot + (slot - barW) / 2;
      const dow = orderIdx[i];
      const isWeekend = dow === 0 || dow === 6;
      const isMax = i === maxIdx && v != null;
      let fill = hexToRgba(color, 0.55);
      if (isWeekend) fill = hexToRgba(color, 0.4);
      if (isMax) fill = color;
      if (v != null && maxAvg > 0) {
        const h = v / maxAvg * plotH;
        const y = plotTop + valueLabelH + plotH - h;
        ctx.fillStyle = fill;
        ctx.beginPath();
        ctx.roundRect(x, y, barW, h, [cornerR, cornerR, 0, 0]);
        ctx.fill();
        if (slot >= 42) {
          ctx.fillStyle = isMax ? theme.fg : theme.muted;
          ctx.font = isMax ? "600 10px sans-serif" : "10px sans-serif";
          ctx.textAlign = "center";
          ctx.textBaseline = "bottom";
          ctx.fillText(meta.format(v), x + barW / 2, y - 3);
        }
      } else {
        ctx.fillStyle = hexToRgba(color, 0.1);
        ctx.beginPath();
        ctx.roundRect(x, plotBottom - 3, barW, 3, 2);
        ctx.fill();
      }
      ctx.fillStyle = isWeekend ? theme.muted : theme.fg;
      ctx.font = "11px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "top";
      ctx.fillText(initials[i], x + barW / 2, plotBottom + 4);
      hits.add({
        shape: "rect",
        x: padL + i * slot,
        y: plotTop,
        w: slot,
        // Include the x-axis label area so clicking “Tuesday” behaves the
        // same as clicking the Tuesday bar.
        h: plotBottom + axisH - plotTop,
        title: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][dow],
        details: v != null ? [
          { label: "Average", value: `${meta.format(v)} ${meta.unit}` },
          { label: "Samples", value: `${counts[i]}` }
        ] : [
          { label: "Status", value: "No data" }
        ],
        payload: buckets[dow].dates
      });
    }
    const bestLabel = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][orderIdx[maxIdx]];
    const worstIdx = avgs.reduce(
      (best, v, i) => {
        var _a2;
        return v != null && (avgs[best] == null || v < ((_a2 = avgs[best]) != null ? _a2 : Infinity)) ? i : best;
      },
      0
    );
    const worstLabel = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][orderIdx[worstIdx]];
    const bestValue = avgs[maxIdx];
    const worstValue = avgs[worstIdx];
    renderStatBoxes(statsEl, [
      { value: meta.format(overallMean), label: "Overall mean" },
      {
        value: bestLabel,
        label: `Best (${bestValue != null ? meta.format(bestValue) : "\u2014"})`
      },
      {
        value: worstLabel,
        label: `Lowest (${worstValue != null ? meta.format(worstValue) : "\u2014"})`
      },
      { value: String(totalSamples), label: "Days sampled" }
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/oxygen-range.ts
  function specFor(metric) {
    if (metric === "respiratory-rate") {
      return {
        label: "Respiratory Rate",
        unit: "brpm",
        capsuleColor: "#3bb2c1",
        padL: 40,
        avgDotInnerLightFill: "#0a1a22",
        extract: (d) => {
          var _a, _b, _c;
          const v = d.vitals;
          if (!v) return null;
          const avg3 = (_a = v.respiratoryRateAvg) != null ? _a : v.respiratoryRate;
          if (avg3 == null || avg3 <= 0) return null;
          return { min: (_b = v.respiratoryRateMin) != null ? _b : avg3, max: (_c = v.respiratoryRateMax) != null ? _c : avg3, avg: avg3 };
        },
        yAxis: ({ min, max }) => ({
          yMin: Math.min(10, Math.floor(min - 1)),
          yMax: Math.max(25, Math.ceil(max + 1)),
          gridStep: 5
        }),
        formatAxisLabel: (v) => String(v),
        formatValue: (v) => v.toFixed(1),
        warn: { hi: 20, color: "#ff3b30", note: "Elevated >20 brpm" },
        stats: { lowColor: "#3bb2c1", avgColor: "#3bb2c1", highColor: "#3bb2c1" }
      };
    }
    return {
      label: "Blood Oxygen",
      unit: "%",
      capsuleColor: "#1eeaef",
      padL: 40,
      avgDotInnerLightFill: "#0a1a22",
      extract: (d) => {
        var _a, _b, _c;
        const v = d.vitals;
        if (!v) return null;
        const avg3 = (_a = v.bloodOxygenAvg) != null ? _a : v.bloodOxygenPercent;
        if (avg3 == null || avg3 <= 0) return null;
        return { min: (_b = v.bloodOxygenMin) != null ? _b : avg3, max: (_c = v.bloodOxygenMax) != null ? _c : avg3, avg: avg3 };
      },
      yAxis: ({ min, max }) => ({
        yMin: Math.min(90, Math.floor(min - 1)),
        yMax: Math.max(100, Math.ceil(max + 1)),
        gridStep: 2
      }),
      formatAxisLabel: (v) => String(v),
      formatValue: (v) => v.toFixed(1),
      warn: { lo: 95, color: "#ff3b30", note: "Low SpO\u2082 <95%" },
      stats: { lowColor: "#1eeaef", avgColor: "#1eeaef", highColor: "#1eeaef" }
    };
  }
  var renderOxygenRange = (ctx, data, W, H, config, theme, statsEl, hits) => {
    const metric = config.metric || "blood-oxygen";
    renderRangeChart(ctx, data, W, H, theme, statsEl, hits, specFor(metric));
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/workout-zones.ts
  var ZONE_HUES = [210, 180, 120, 40, 0];
  var DEFAULT_ZONE_LABELS = ["Recovery", "Aerobic", "Tempo", "Threshold", "Max"];
  var DEFAULT_ZONE_FRACTIONS = [0.5, 0.6, 0.7, 0.8, 0.9, 1.01];
  function resolveMaxHeartRate(config, theme) {
    const cfg = config.maxHeartRate;
    if (typeof cfg === "number" && cfg > 0) return cfg;
    if (typeof cfg === "string") {
      const n = parseInt(cfg, 10);
      if (Number.isFinite(n) && n > 0) return n;
    }
    return theme.maxHeartRate;
  }
  function formatZoneDuration(zone) {
    var _a;
    return (_a = zone.durationFormatted) != null ? _a : formatDuration(zone.seconds);
  }
  function zonesFromSamples(samples, maxHr) {
    if (!samples.length || !maxHr) return [];
    const zones = DEFAULT_ZONE_LABELS.map((label, idx) => ({
      index: idx + 1,
      label,
      range: `${Math.round(maxHr * DEFAULT_ZONE_FRACTIONS[idx])}-${Math.round(maxHr * DEFAULT_ZONE_FRACTIONS[idx + 1])}`,
      seconds: 0
    }));
    for (let i = 0; i < samples.length; i++) {
      const current = samples[i];
      const next = samples[i + 1];
      const currentMs = Date.parse(current.timestamp);
      const nextMs = next ? Date.parse(next.timestamp) : NaN;
      const seconds = Number.isFinite(currentMs) && Number.isFinite(nextMs) ? Math.max(1, Math.min(300, (nextMs - currentMs) / 1e3)) : 60;
      const frac = current.value / maxHr;
      let zoneIndex = zones.findIndex((zone, idx) => frac >= DEFAULT_ZONE_FRACTIONS[idx] && frac < DEFAULT_ZONE_FRACTIONS[idx + 1]);
      if (zoneIndex === -1 && frac >= 1) zoneIndex = zones.length - 1;
      if (zoneIndex !== -1) zones[zoneIndex].seconds += seconds;
    }
    return zones.filter((zone) => zone.seconds > 0);
  }
  var renderWorkoutZones = (ctx, data, W, H, config, theme, statsEl, hits) => {
    var _a, _b, _c, _d;
    const picked = pickWorkout(data, config);
    if (!picked) {
      drawEmptyState(ctx, W, H, theme.bg, theme.muted, "No workout found");
      statsEl.empty();
      return;
    }
    const { day, workout } = picked;
    const zones = ((_a = workout.heartRateZones) != null ? _a : []).filter((zone) => zone.seconds > 0);
    const fallbackZones = zones.length ? [] : zonesFromSamples((_c = (_b = workout.timeSeries) == null ? void 0 : _b.heartRate) != null ? _c : [], resolveMaxHeartRate(config, theme));
    const visibleZones = zones.length ? zones : fallbackZones;
    if (!visibleZones.length) {
      drawEmptyState(ctx, W, H, theme.bg, theme.muted, "No heart-rate zones for this workout");
      statsEl.empty();
      return;
    }
    const minH = 132;
    if (H < minH) {
      const dpr = activeWindow.devicePixelRatio || 1;
      ctx.canvas.width = W * dpr;
      ctx.canvas.height = minH * dpr;
      ctx.canvas.style.width = W + "px";
      ctx.canvas.style.height = minH + "px";
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
      H = minH;
    }
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const total = visibleZones.reduce((sum, zone) => sum + zone.seconds, 0);
    const padX = 28;
    const titleY = 14;
    const barY = Math.max(52, H * 0.32);
    const barH = Math.min(34, Math.max(22, H * 0.14));
    const barW = W - padX * 2;
    const radius = barH / 2;
    ctx.fillStyle = theme.fg;
    ctx.font = "600 13px sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.fillText(`${(_d = workout.activityType) != null ? _d : workout.type} zones`, padX, titleY);
    ctx.fillStyle = theme.muted;
    ctx.font = "10px sans-serif";
    ctx.fillText(day.date, padX, titleY + 18);
    ctx.save();
    ctx.beginPath();
    ctx.roundRect(padX, barY, barW, barH, radius);
    ctx.clip();
    let x = padX;
    visibleZones.forEach((zone) => {
      const w = zone.seconds / total * barW;
      const hue = ZONE_HUES[(zone.index - 1 + ZONE_HUES.length) % ZONE_HUES.length];
      ctx.fillStyle = `hsl(${hue},70%,${theme.isDark ? 52 : 46}%)`;
      ctx.fillRect(x, barY, Math.max(0, w), barH);
      if (w > 42) {
        ctx.fillStyle = hexToRgba("#ffffff", 0.92);
        ctx.font = "700 10px sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(`Z${zone.index}`, x + w / 2, barY + barH / 2);
      }
      hits.add({
        shape: "rect",
        x,
        y: barY,
        w: Math.max(1, w),
        h: barH,
        title: `Zone ${zone.index} \u2014 ${zone.label}`,
        details: [
          { label: "Time", value: formatZoneDuration(zone) },
          { label: "Share", value: `${Math.round(zone.seconds / total * 100)}%` },
          ...zone.range ? [{ label: "Range", value: `${zone.range} bpm` }] : []
        ],
        payload: day
      });
      x += w;
    });
    ctx.restore();
    const legendY = barY + barH + 22;
    const colW = barW / visibleZones.length;
    visibleZones.forEach((zone, idx) => {
      const hue = ZONE_HUES[(zone.index - 1 + ZONE_HUES.length) % ZONE_HUES.length];
      const lx = padX + idx * colW;
      ctx.fillStyle = `hsl(${hue},70%,${theme.isDark ? 58 : 42}%)`;
      ctx.beginPath();
      ctx.arc(lx + 5, legendY + 4, 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = theme.fg;
      ctx.font = "700 10px sans-serif";
      ctx.textAlign = "left";
      ctx.textBaseline = "top";
      ctx.fillText(`Z${zone.index}`, lx + 14, legendY - 1);
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.fillText(formatZoneDuration(zone), lx + 14, legendY + 12);
    });
    const dominant = visibleZones.reduce((best, zone) => zone.seconds > best.seconds ? zone : best, visibleZones[0]);
    renderInlineStats(statsEl, [
      [
        { text: "Zone time " },
        { text: formatDuration(total), strong: true }
      ],
      [
        { text: "Dominant " },
        { text: `Z${dominant.index} ${dominant.label}`, strong: true }
      ]
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/workout-heart-rate.ts
  var ZONES = [
    { label: "Z1", loFrac: 0.5, hiFrac: 0.6, hue: 210 },
    { label: "Z2", loFrac: 0.6, hiFrac: 0.7, hue: 180 },
    { label: "Z3", loFrac: 0.7, hiFrac: 0.8, hue: 120 },
    { label: "Z4", loFrac: 0.8, hiFrac: 0.9, hue: 40 },
    { label: "Z5", loFrac: 0.9, hiFrac: 1, hue: 0 }
  ];
  function zoneFor(bpm, maxHr) {
    const frac = bpm / maxHr;
    for (const z of ZONES) {
      if (frac >= z.loFrac && frac < z.hiFrac) return z;
    }
    if (frac >= 1) return ZONES[ZONES.length - 1];
    return null;
  }
  function resolveMaxHeartRate2(config, theme) {
    const cfg = config.maxHeartRate;
    if (typeof cfg === "number" && cfg > 0) return cfg;
    if (typeof cfg === "string") {
      const n = parseInt(cfg, 10);
      if (Number.isFinite(n) && n > 0) return n;
    }
    return theme.maxHeartRate;
  }
  function resolveWorkoutEndMs(picked) {
    var _a;
    const { workout } = picked;
    if (workout.endTimeISO) {
      const endMs = Date.parse(workout.endTimeISO);
      if (Number.isFinite(endMs)) return endMs;
    }
    const start = (_a = workout.startTimeISO) != null ? _a : workout.startTime;
    const startMs = start ? Date.parse(start) : NaN;
    if (Number.isFinite(startMs) && Number.isFinite(workout.duration)) {
      return startMs + workout.duration * 1e3;
    }
    return NaN;
  }
  function dailySamplesForWorkout(picked) {
    var _a, _b, _c;
    const dailySamples = (_b = (_a = picked.day.heart) == null ? void 0 : _a.heartRateSamples) != null ? _b : [];
    if (!dailySamples.length) return [];
    const start = (_c = picked.workout.startTimeISO) != null ? _c : picked.workout.startTime;
    const startMs = start ? Date.parse(start) : NaN;
    const endMs = resolveWorkoutEndMs(picked);
    if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs) {
      return [];
    }
    const edgeToleranceMs = 6e4;
    return dailySamples.filter((sample) => {
      const sampleMs = Date.parse(sample.timestamp);
      return Number.isFinite(sampleMs) && Number.isFinite(sample.value) && sampleMs >= startMs - edgeToleranceMs && sampleMs <= endMs + edgeToleranceMs;
    }).sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp));
  }
  function heartRateSampleSources(picked) {
    var _a, _b;
    const sources = [];
    const workoutSamples = (_b = (_a = picked.workout.timeSeries) == null ? void 0 : _a.heartRate) != null ? _b : [];
    if (workoutSamples.length) {
      sources.push({ samples: workoutSamples, source: "workout" });
    }
    const dailySamples = dailySamplesForWorkout(picked);
    if (dailySamples.length) {
      sources.push({ samples: dailySamples, source: "daily" });
    }
    return sources;
  }
  function elapsedPoints(samples, workoutStart) {
    return samples.map((sample) => ({
      t: elapsedSeconds(workoutStart, sample.timestamp),
      v: sample.value
    })).filter((point) => Number.isFinite(point.t) && Number.isFinite(point.v) && point.t >= 0).sort((a, b) => a.t - b.t);
  }
  function medianGapSeconds(pts) {
    const gaps = [];
    for (let i = 1; i < pts.length; i++) {
      const gap = pts[i].t - pts[i - 1].t;
      if (gap > 0) gaps.push(gap);
    }
    if (!gaps.length) return 0;
    gaps.sort((a, b) => a - b);
    return gaps[Math.floor(gaps.length / 2)];
  }
  function drawSummaryFallback(ctx, W, H, theme, stats, maxHr) {
    const values = [stats.lo, stats.avg, stats.hi].filter(
      (value) => typeof value === "number" && Number.isFinite(value)
    );
    if (!values.length) {
      drawEmptyState(ctx, W, H, theme.bg, theme.muted, "No heart rate data for this workout");
      return;
    }
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const padL = 44;
    const padR = 18;
    const padT = 46;
    const padB = 34;
    const plotW2 = W - padL - padR;
    const plotH = Math.max(24, H - padT - padB);
    const axisY = padT + plotH * 0.58;
    let xMin = Math.max(0, Math.floor(Math.min(...values) - 8));
    let xMax = Math.ceil(Math.max(...values) + 8);
    if (maxHr) {
      xMin = Math.min(xMin, Math.floor(maxHr * ZONES[0].loFrac));
      xMax = Math.max(xMax, Math.ceil(maxHr));
    }
    if (xMax - xMin < 20) xMax = xMin + 20;
    const xFor = (bpm) => padL + (bpm - xMin) / (xMax - xMin || 1) * plotW2;
    ctx.fillStyle = theme.fg;
    ctx.font = "600 13px sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.fillText("Workout heart-rate summary", padL, 12);
    ctx.fillStyle = theme.muted;
    ctx.font = "11px sans-serif";
    ctx.fillText("Detailed heart-rate samples were not included in this export.", padL, 29);
    if (maxHr) {
      for (const z of ZONES) {
        const lo = maxHr * z.loFrac;
        const hi = maxHr * z.hiFrac;
        if (hi <= xMin || lo >= xMax) continue;
        const x0 = xFor(Math.max(lo, xMin));
        const x1 = xFor(Math.min(hi, xMax));
        ctx.fillStyle = `hsla(${z.hue},70%,${theme.isDark ? 40 : 70}%,0.12)`;
        ctx.fillRect(x0, padT, x1 - x0, plotH);
        ctx.fillStyle = `hsla(${z.hue},70%,${theme.isDark ? 70 : 40}%,0.58)`;
        ctx.font = "9px sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "top";
        ctx.fillText(z.label, (x0 + x1) / 2, padT + 4);
      }
    }
    ctx.strokeStyle = hexToRgba(theme.fg, 0.08);
    ctx.fillStyle = theme.muted;
    ctx.font = "9px sans-serif";
    ctx.lineWidth = 1;
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    const xRange = xMax - xMin;
    const xStep = xRange <= 40 ? 10 : xRange <= 100 ? 20 : 40;
    const tickStart = Math.ceil(xMin / xStep) * xStep;
    for (let bpm = tickStart; bpm <= xMax; bpm += xStep) {
      const x = xFor(bpm);
      ctx.beginPath();
      ctx.moveTo(x, padT);
      ctx.lineTo(x, padT + plotH);
      ctx.stroke();
      ctx.fillText(String(bpm), x, padT + plotH + 6);
    }
    ctx.strokeStyle = hexToRgba(theme.fg, 0.14);
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(padL, axisY);
    ctx.lineTo(padL + plotW2, axisY);
    ctx.stroke();
    if (stats.lo != null && stats.hi != null) {
      ctx.strokeStyle = hexToRgba(theme.colors.heart, 0.72);
      ctx.lineWidth = 9;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(xFor(stats.lo), axisY);
      ctx.lineTo(xFor(stats.hi), axisY);
      ctx.stroke();
      ctx.lineCap = "butt";
    }
    const markers = [
      { value: stats.lo, label: "MIN", color: "#4488ff", yOffset: 22 },
      { value: stats.avg, label: "AVG", color: theme.colors.heart, yOffset: -28 },
      { value: stats.hi, label: "MAX", color: "#ff4444", yOffset: 22 }
    ];
    for (const marker of markers) {
      if (marker.value == null || !Number.isFinite(marker.value)) continue;
      const x = xFor(marker.value);
      ctx.fillStyle = marker.color;
      ctx.beginPath();
      ctx.arc(x, axisY, marker.label === "AVG" ? 6 : 4.5, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = marker.color;
      ctx.font = "700 11px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = marker.yOffset < 0 ? "bottom" : "top";
      ctx.fillText(`${Math.round(marker.value)} BPM`, x, axisY + marker.yOffset);
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textBaseline = marker.yOffset < 0 ? "bottom" : "top";
      ctx.fillText(marker.label, x, axisY + marker.yOffset + (marker.yOffset < 0 ? -13 : 14));
    }
  }
  var renderWorkoutHeartRate = (ctx, data, W, H, config, theme, statsEl, hits) => {
    var _a, _b;
    const picked = pickWorkout(data, config);
    if (!picked) {
      drawEmptyState(ctx, W, H, theme.bg, theme.muted, "No workout found");
      statsEl.empty();
      return;
    }
    const { workout } = picked;
    const maxHr = resolveMaxHeartRate2(config, theme);
    const workoutStart = (_a = workout.startTimeISO) != null ? _a : workout.startTime;
    const sources = heartRateSampleSources(picked);
    let pts = [];
    let sampleSource = null;
    for (const source of sources) {
      const candidate = elapsedPoints(source.samples, workoutStart);
      if (candidate.length) {
        pts = candidate;
        sampleSource = source.source;
        break;
      }
    }
    if (!pts.length) {
      if ((_b = workout.heartRateZones) == null ? void 0 : _b.some((zone) => zone.seconds > 0)) {
        renderWorkoutZones(ctx, data, W, H, config, theme, statsEl, hits);
        return;
      }
      const avg4 = workout.avgHeartRate;
      const lo2 = workout.minHeartRate;
      const hi2 = workout.maxHeartRate;
      if (avg4 == null && lo2 == null && hi2 == null) {
        drawEmptyState(
          ctx,
          W,
          H,
          theme.bg,
          theme.muted,
          "No heart rate data for this workout"
        );
        statsEl.empty();
        return;
      }
      drawSummaryFallback(ctx, W, H, theme, { lo: lo2, avg: avg4, hi: hi2 }, maxHr);
      const boxes = [];
      if (lo2 != null) boxes.push({ value: String(lo2), label: "Min", color: "#4488ff" });
      if (avg4 != null)
        boxes.push({ value: String(Math.round(avg4)), label: "Avg", color: theme.colors.heart });
      if (hi2 != null) boxes.push({ value: String(hi2), label: "Max", color: "#ff4444" });
      renderStatBoxes(statsEl, boxes);
      return;
    }
    let minBpm = Infinity;
    let maxBpm = -Infinity;
    for (const p of pts) {
      if (p.v < minBpm) minBpm = p.v;
      if (p.v > maxBpm) maxBpm = p.v;
    }
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const tMax = Math.max(workout.duration || 0, pts[pts.length - 1].t);
    const tMin = 0;
    let yMin = Math.max(0, Math.floor(minBpm - 5));
    let yMax = Math.ceil(maxBpm + 5);
    if (maxHr) {
      yMin = Math.min(yMin, Math.floor(maxHr * ZONES[0].loFrac));
      yMax = Math.max(yMax, Math.ceil(maxHr));
    }
    if (yMax - yMin < 20) yMax = yMin + 20;
    const padL = 44;
    const padR = 14;
    const padT = 14;
    const padB = 22;
    const plotW2 = W - padL - padR;
    const plotH = H - padT - padB;
    const xFor = (t) => padL + (t - tMin) / (tMax - tMin || 1) * plotW2;
    const yFor = (v) => padT + (1 - (v - yMin) / (yMax - yMin || 1)) * plotH;
    if (maxHr) {
      for (const z of ZONES) {
        const lo2 = maxHr * z.loFrac;
        const hi2 = maxHr * z.hiFrac;
        if (hi2 <= yMin || lo2 >= yMax) continue;
        const yTop = yFor(Math.min(hi2, yMax));
        const yBot = yFor(Math.max(lo2, yMin));
        ctx.fillStyle = `hsla(${z.hue},70%,${theme.isDark ? 40 : 70}%,0.13)`;
        ctx.fillRect(padL, yTop, plotW2, yBot - yTop);
        ctx.fillStyle = `hsla(${z.hue},70%,${theme.isDark ? 70 : 40}%,0.6)`;
        ctx.font = "9px sans-serif";
        ctx.textAlign = "right";
        ctx.textBaseline = "middle";
        ctx.fillText(z.label, padL + plotW2 - 3, (yTop + yBot) / 2);
      }
    }
    ctx.strokeStyle = hexToRgba(theme.fg, 0.07);
    ctx.fillStyle = theme.muted;
    ctx.font = "9px sans-serif";
    ctx.lineWidth = 1;
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";
    const yRange = yMax - yMin;
    const yStep = yRange <= 40 ? 10 : yRange <= 100 ? 20 : 40;
    const yStart = Math.ceil(yMin / yStep) * yStep;
    for (let v = yStart; v <= yMax; v += yStep) {
      const y = yFor(v);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(padL + plotW2, y);
      ctx.stroke();
      ctx.fillText(String(v), padL - 4, y);
    }
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    const tStep = tMax <= 600 ? 60 : tMax <= 1800 ? 300 : tMax <= 3600 ? 600 : 1800;
    for (let t = 0; t <= tMax; t += tStep) {
      const x = xFor(t);
      ctx.strokeStyle = hexToRgba(theme.fg, 0.05);
      ctx.beginPath();
      ctx.moveTo(x, padT);
      ctx.lineTo(x, padT + plotH);
      ctx.stroke();
      ctx.fillStyle = theme.muted;
      ctx.fillText(formatElapsed(t), x, padT + plotH + 4);
    }
    ctx.strokeStyle = theme.colors.heart;
    ctx.lineWidth = 1.5;
    ctx.lineJoin = "round";
    ctx.lineCap = "round";
    ctx.beginPath();
    let prevT = -Infinity;
    const medianGap = medianGapSeconds(pts);
    const GAP_THRESHOLD = Math.max(60, medianGap ? medianGap * 2.5 : 60);
    for (let i = 0; i < pts.length; i++) {
      const p = pts[i];
      const x = xFor(p.t);
      const y = yFor(p.v);
      if (p.t - prevT > GAP_THRESHOLD) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
      prevT = p.t;
    }
    ctx.stroke();
    if (pts.length <= 120 || sampleSource === "daily") {
      ctx.fillStyle = theme.colors.heart;
      for (const p of pts) {
        ctx.beginPath();
        ctx.arc(xFor(p.t), yFor(p.v), sampleSource === "daily" ? 2.5 : 2, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    const STRIDE = 4;
    for (let x = padL; x < padL + plotW2; x += STRIDE) {
      const tCenter = tMin + (x + STRIDE / 2 - padL) / plotW2 * (tMax - tMin);
      let bestIdx = 0;
      let bestDist = Infinity;
      for (let i = 0; i < pts.length; i++) {
        const d = Math.abs(pts[i].t - tCenter);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        } else if (d > bestDist) {
          break;
        }
      }
      const p = pts[bestIdx];
      const details = [
        { label: "Time", value: formatElapsed(p.t) },
        { label: "BPM", value: String(Math.round(p.v)) }
      ];
      if (maxHr) {
        const z = zoneFor(p.v, maxHr);
        details.push({ label: "Zone", value: z ? z.label : "below Z1" });
      }
      if (sampleSource === "daily") {
        details.push({ label: "Source", value: "daily samples" });
      }
      hits.add({
        shape: "rect",
        x,
        y: padT,
        w: STRIDE,
        h: plotH,
        title: "Heart rate",
        details,
        payload: picked.day
      });
    }
    const avg3 = pts.reduce((s, p) => s + p.v, 0) / pts.length;
    const lo = Math.round(minBpm);
    const hi = Math.round(maxBpm);
    const rows = [
      [
        { text: "Average " },
        { text: `${Math.round(avg3)} BPM`, strong: true }
      ],
      [{ text: `Range: ${lo}\u2013${hi} BPM` }]
    ];
    if (maxHr) {
      rows.push([
        { text: "Max HR " },
        { text: `${maxHr} BPM`, strong: true }
      ]);
    }
    if (sampleSource === "daily") {
      rows.push([{ text: "Source: daily heart-rate samples within workout time" }]);
    }
    renderInlineStats(statsEl, rows);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/workout-trends.ts
  var METRICS5 = [
    {
      key: "duration",
      label: "Duration",
      unit: "min",
      color: (theme) => theme.colors.accent,
      value: (workout) => workout.duration > 0 ? workout.duration / 60 : void 0,
      format: (value) => formatDuration(value * 60)
    },
    {
      key: "distance",
      label: "Distance",
      unit: "km",
      color: (theme) => theme.colors.secondary,
      value: (workout) => {
        const meters = workoutDistanceMeters(workout);
        return meters == null ? void 0 : meters / 1e3;
      },
      format: (value) => `${value.toFixed(value >= 10 ? 1 : 2)} km`
    },
    {
      key: "calories",
      label: "Calories",
      unit: "kcal",
      color: () => "#f97316",
      value: (workout) => workout.calories,
      format: (value) => `${Math.round(value)} kcal`
    },
    {
      key: "hr_avg",
      label: "Avg HR",
      unit: "bpm",
      color: (theme) => theme.colors.heart,
      value: (workout) => workout.avgHeartRate,
      format: (value) => `${Math.round(value)} BPM`
    },
    {
      key: "power_avg",
      label: "Avg Power",
      unit: "W",
      color: () => "#a855f7",
      value: (workout) => workout.avgPower,
      format: (value) => `${Math.round(value)} W`
    }
  ];
  function metricAliases(raw) {
    const normalized = raw.trim().toLowerCase().replace(/[\s-]+/g, "_");
    switch (normalized) {
      case "hr":
      case "heart_rate":
      case "avg_heart_rate":
        return "hr_avg";
      case "power":
      case "avg_power":
        return "power_avg";
      case "cal":
      case "energy":
        return "calories";
      default:
        return normalized;
    }
  }
  function collectWorkoutPoints(data) {
    var _a, _b, _c;
    const points = [];
    for (const day of data) {
      for (const workout of (_a = day.workouts) != null ? _a : []) {
        const timestamp = (_c = (_b = workout.startTimeISO) != null ? _b : workout.startTime) != null ? _c : `${day.date}T00:00:00`;
        const ms = Date.parse(timestamp);
        points.push({
          day,
          workout,
          timestamp,
          ms: Number.isFinite(ms) ? ms : Date.parse(`${day.date}T00:00:00`)
        });
      }
    }
    return points.sort((a, b) => a.ms - b.ms);
  }
  function niceStep(range) {
    if (range <= 5) return 1;
    if (range <= 20) return 5;
    if (range <= 60) return 10;
    if (range <= 200) return 25;
    return 50;
  }
  function drawPanel(ctx, points, metric, x, y, w, h, theme, hits) {
    const values = [];
    for (const point of points) {
      const value = metric.value(point.workout);
      if (value !== void 0 && Number.isFinite(value)) {
        values.push({ ...point, value });
      }
    }
    if (!values.length) return;
    const minMs = values[0].ms;
    const maxMs = values[values.length - 1].ms;
    let minValue = Math.min(...values.map((point) => point.value));
    let maxValue = Math.max(...values.map((point) => point.value));
    if (minValue === maxValue) {
      minValue = Math.max(0, minValue * 0.8 - 1);
      maxValue = maxValue * 1.2 + 1;
    }
    if (minValue > 0) minValue = Math.max(0, minValue - (maxValue - minValue) * 0.12);
    maxValue += (maxValue - minValue) * 0.12;
    const xFor = (ms) => x + (ms - minMs) / (maxMs - minMs || 1) * w;
    const yFor = (value) => y + (1 - (value - minValue) / (maxValue - minValue || 1)) * h;
    const color = metric.color(theme);
    ctx.fillStyle = theme.fg;
    ctx.font = "600 11px sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.fillText(metric.label, x, y - 18);
    ctx.fillStyle = theme.muted;
    ctx.font = "9px sans-serif";
    ctx.textAlign = "right";
    ctx.fillText(metric.unit, x + w, y - 17);
    ctx.strokeStyle = hexToRgba(theme.fg, 0.08);
    ctx.lineWidth = 1;
    const step = niceStep(maxValue - minValue);
    const start = Math.ceil(minValue / step) * step;
    for (let tick = start; tick <= maxValue; tick += step) {
      const ty = yFor(tick);
      ctx.beginPath();
      ctx.moveTo(x, ty);
      ctx.lineTo(x + w, ty);
      ctx.stroke();
    }
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.lineJoin = "round";
    ctx.lineCap = "round";
    ctx.beginPath();
    values.forEach((point, index) => {
      const px = xFor(point.ms);
      const py = yFor(point.value);
      if (index === 0) ctx.moveTo(px, py);
      else ctx.lineTo(px, py);
    });
    ctx.stroke();
    ctx.fillStyle = color;
    values.forEach((point) => {
      var _a;
      const px = xFor(point.ms);
      const py = yFor(point.value);
      ctx.beginPath();
      ctx.arc(px, py, 3.5, 0, Math.PI * 2);
      ctx.fill();
      hits.add({
        shape: "circle",
        cx: px,
        cy: py,
        r: 8,
        title: `${formatDate(point.day.date)} \u2014 ${(_a = point.workout.activityType) != null ? _a : point.workout.type}`,
        details: [
          { label: metric.label, value: metric.format(point.value) },
          { label: "Duration", value: formatDuration(point.workout.duration) },
          ...point.workout.calories != null ? [{ label: "Calories", value: `${Math.round(point.workout.calories)} kcal` }] : []
        ],
        payload: point.day
      });
    });
    ctx.fillStyle = theme.muted;
    ctx.font = "8px sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.fillText(formatDate(values[0].day.date), x, y + h + 4);
    ctx.textAlign = "right";
    ctx.fillText(formatDate(values[values.length - 1].day.date), x + w, y + h + 4);
  }
  var renderWorkoutTrends = (ctx, data, W, H, config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const points = collectWorkoutPoints(data);
    if (!points.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText("No workouts in range", W / 2, H / 2);
      statsEl.empty();
      return;
    }
    const metricRaw = config.metric == null ? "all" : String(config.metric);
    const requested = metricAliases(metricRaw);
    const metrics = requested === "all" ? METRICS5.filter((metric) => points.some((point) => metric.value(point.workout) !== void 0)) : METRICS5.filter((metric) => metric.key === requested);
    if (!metrics.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(`No workout data for metric: ${metricRaw}`, W / 2, H / 2);
      statsEl.empty();
      return;
    }
    const padL = 34;
    const padR = 18;
    const padT = 52;
    const padB = 22;
    const gap = metrics.length > 1 ? 34 : 18;
    const minPanelH = metrics.length > 1 ? 32 : 90;
    const neededH = padT + padB + gap * (metrics.length - 1) + minPanelH * metrics.length;
    if (H < neededH) {
      const dpr = activeWindow.devicePixelRatio || 1;
      ctx.canvas.width = W * dpr;
      ctx.canvas.height = neededH * dpr;
      ctx.canvas.style.width = W + "px";
      ctx.canvas.style.height = neededH + "px";
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
      H = neededH;
      ctx.fillStyle = theme.bg;
      ctx.fillRect(0, 0, W, H);
    }
    const panelH = Math.max(minPanelH, (H - padT - padB - gap * (metrics.length - 1)) / metrics.length);
    const panelW = W - padL - padR;
    ctx.fillStyle = theme.fg;
    ctx.font = "700 13px sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.fillText("Workout trends", padL, 10);
    metrics.forEach((metric, index) => {
      drawPanel(ctx, points, metric, padL, padT + index * (panelH + gap), panelW, Math.max(24, panelH), theme, hits);
    });
    const totalDuration = points.reduce((sum, point) => sum + (point.workout.duration || 0), 0);
    const totalDistanceMeters = points.reduce((sum, point) => {
      var _a;
      return sum + ((_a = workoutDistanceMeters(point.workout)) != null ? _a : 0);
    }, 0);
    renderInlineStats(statsEl, [
      [{ text: `${points.length} workouts` }],
      [
        { text: "Total time " },
        { text: formatDuration(totalDuration), strong: true }
      ],
      ...totalDistanceMeters > 0 ? [[{ text: "Distance " }, { text: `${(totalDistanceMeters / 1e3).toFixed(1)} km`, strong: true }]] : []
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/workout-map.ts
  var L2 = __toESM(require_leaflet_src());
  var MAX_POINTS = 1500;
  function downsample(arr, max) {
    if (arr.length <= max) return arr;
    const stride = arr.length / max;
    const out = [];
    for (let i = 0; i < max - 1; i++) {
      out.push(arr[Math.floor(i * stride)]);
    }
    out.push(arr[arr.length - 1]);
    return out;
  }
  function haversine(a, b) {
    const R = 6371e3;
    const toRad = (deg) => deg * Math.PI / 180;
    const dLat = toRad(b.latitude - a.latitude);
    const dLon = toRad(b.longitude - a.longitude);
    const lat1 = toRad(a.latitude);
    const lat2 = toRad(b.latitude);
    const h = Math.sin(dLat / 2) ** 2 + Math.sin(dLon / 2) ** 2 * Math.cos(lat1) * Math.cos(lat2);
    return 2 * R * Math.asin(Math.sqrt(h));
  }
  function computeValues(route, colorBy, hrSamples) {
    const values = new Array(route.length).fill(0);
    let min = Infinity;
    let max = -Infinity;
    if (colorBy === "hr" && hrSamples && hrSamples.length) {
      const hrTimes = hrSamples.map((s) => Date.parse(s.timestamp));
      for (let i = 0; i < route.length; i++) {
        const t = Date.parse(route[i].timestamp);
        let lo = 0;
        let hi = hrTimes.length - 1;
        while (lo < hi) {
          const mid = lo + hi >> 1;
          if (hrTimes[mid] < t) lo = mid + 1;
          else hi = mid;
        }
        let idx = lo;
        if (idx > 0 && Math.abs(hrTimes[idx - 1] - t) < Math.abs(hrTimes[idx] - t)) {
          idx = idx - 1;
        }
        values[i] = hrSamples[idx].value;
        if (values[i] < min) min = values[i];
        if (values[i] > max) max = values[i];
      }
    } else {
      for (let i = 0; i < route.length; i++) {
        const p = route[i];
        let v = p.speedMps;
        if (v == null && i > 0) {
          const prev = route[i - 1];
          const dt = (Date.parse(p.timestamp) - Date.parse(prev.timestamp)) / 1e3;
          if (dt > 0) v = haversine(prev, p) / dt;
        }
        values[i] = v != null ? v : 0;
        if (values[i] < min) min = values[i];
        if (values[i] > max) max = values[i];
      }
    }
    if (!Number.isFinite(min) || !Number.isFinite(max)) {
      return { values, min: 0, max: 1 };
    }
    if (max - min < 1e-4) max = min + 1;
    return { values, min, max };
  }
  function colorForValue(t) {
    const hue = (1 - Math.max(0, Math.min(1, t))) * 240;
    return `hsl(${hue},75%,50%)`;
  }
  function totalRouteDistance(route) {
    let d = 0;
    for (let i = 1; i < route.length; i++) {
      d += haversine(route[i - 1], route[i]);
    }
    return d;
  }
  function renderHeader(host, day, workout) {
    var _a, _b;
    const header = host.createDiv({ cls: "health-md-workout-header" });
    const title = header.createDiv({ cls: "health-md-workout-title" });
    title.textContent = workout.type ? workout.type.charAt(0).toUpperCase() + workout.type.slice(1) : "Workout";
    const stats = header.createDiv({ cls: "health-md-workout-stats" });
    const addStat2 = (label, value) => {
      const cell = stats.createDiv({ cls: "health-md-workout-stat" });
      cell.createDiv({ cls: "health-md-workout-stat-label", text: label });
      cell.createDiv({ cls: "health-md-workout-stat-value", text: value });
    };
    const distanceMeters = workoutDistanceMeters(workout);
    const distanceDisplay = formatWorkoutDistance(workout, day);
    if (distanceDisplay) {
      addStat2("Distance", distanceDisplay);
    }
    addStat2("Duration", (_a = workout.durationFormatted) != null ? _a : formatDuration(workout.duration));
    if (distanceMeters != null && workout.duration > 0) {
      addStat2(
        workout.avgSpeedFormatted ? "Avg speed" : "Avg pace",
        (_b = workout.avgSpeedFormatted) != null ? _b : formatPace(distanceMeters, workout.duration, day, workout.avgPaceFormatted)
      );
    }
    if (workout.elevationGainMeters != null) {
      addStat2("Elev gain", formatElevation(workout.elevationGainMeters, day));
    }
    if (workout.elevationLossMeters != null) {
      addStat2("Elev loss", formatElevation(workout.elevationLossMeters, day));
    }
    if (workout.avgHeartRate != null) {
      addStat2("Avg HR", `${Math.round(workout.avgHeartRate)} BPM`);
    }
  }
  function renderEmptyMessage(host, message) {
    const msg = host.createDiv({ cls: "health-md-workout-empty" });
    msg.textContent = message;
  }
  function renderLeafletMap(host, route, colorBy, hrSamples, theme, configHeight) {
    const mapEl = host.createDiv({ cls: "health-md-workout-map" });
    mapEl.style.height = `${configHeight}px`;
    const map2 = L2.map(mapEl, {
      zoomControl: true,
      attributionControl: true,
      scrollWheelZoom: false
    });
    L2.tileLayer(theme.mapTileUrl, {
      attribution: theme.mapTileAttribution,
      maxZoom: 19
    }).addTo(map2);
    const sampled = downsample(route, MAX_POINTS);
    const { values: valuesArr, min: vMin, max: vMax } = computeValues(
      sampled,
      colorBy,
      hrSamples
    );
    for (let i = 1; i < sampled.length; i++) {
      const t = (valuesArr[i] - vMin) / (vMax - vMin || 1);
      L2.polyline(
        [
          [sampled[i - 1].latitude, sampled[i - 1].longitude],
          [sampled[i].latitude, sampled[i].longitude]
        ],
        {
          color: colorForValue(t),
          weight: 4,
          opacity: 0.95,
          lineCap: "round",
          lineJoin: "round"
        }
      ).addTo(map2);
    }
    const start = sampled[0];
    const end = sampled[sampled.length - 1];
    L2.circleMarker([start.latitude, start.longitude], {
      radius: 6,
      color: "#22c55e",
      fillColor: "#22c55e",
      fillOpacity: 1,
      weight: 2
    }).addTo(map2);
    L2.circleMarker([end.latitude, end.longitude], {
      radius: 6,
      color: "#ef4444",
      fillColor: "#ef4444",
      fillOpacity: 1,
      weight: 2
    }).addTo(map2);
    const bounds = L2.latLngBounds(
      sampled.map((p) => [p.latitude, p.longitude])
    );
    map2.fitBounds(bounds, { padding: [20, 20] });
    const legend = mapEl.createDiv({ cls: "health-md-workout-map-legend" });
    const label = colorBy === "hr" ? "HR" : "Speed";
    const lo = colorBy === "hr" ? `${Math.round(vMin)} BPM` : `${(vMin * 3.6).toFixed(1)} km/h`;
    const hi = colorBy === "hr" ? `${Math.round(vMax)} BPM` : `${(vMax * 3.6).toFixed(1)} km/h`;
    legend.textContent = `${label} ${lo} \u2013 ${hi}`;
  }
  function renderCanvasPolyline(host, route, colorBy, hrSamples, theme, width, height) {
    const wrapper = host.createDiv({
      cls: "health-md-workout-map health-md-workout-map-canvas"
    });
    wrapper.style.height = `${height}px`;
    const canvas = wrapper.createEl("canvas");
    const dpr = activeWindow.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.scale(dpr, dpr);
    const sampled = downsample(route, MAX_POINTS);
    const lats = sampled.map((p) => p.latitude);
    const lons = sampled.map((p) => p.longitude);
    const minLat = Math.min(...lats);
    const maxLat = Math.max(...lats);
    const minLon = Math.min(...lons);
    const maxLon = Math.max(...lons);
    const midLat = (minLat + maxLat) / 2;
    const lonScale = Math.cos(midLat * Math.PI / 180);
    const padding = 14;
    const plotW2 = width - padding * 2;
    const plotH = height - padding * 2;
    const lonSpan = (maxLon - minLon) * lonScale || 1e-6;
    const latSpan = maxLat - minLat || 1e-6;
    const scale = Math.min(plotW2 / lonSpan, plotH / latSpan);
    const offX = padding + (plotW2 - lonSpan * scale) / 2;
    const offY = padding + (plotH - latSpan * scale) / 2;
    const project = (p) => [
      offX + (p.longitude - minLon) * lonScale * scale,
      offY + (maxLat - p.latitude) * scale
    ];
    const { values: valuesArr, min: vMin, max: vMax } = computeValues(
      sampled,
      colorBy,
      hrSamples
    );
    ctx.lineWidth = 3;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    for (let i = 1; i < sampled.length; i++) {
      const [x0, y0] = project(sampled[i - 1]);
      const [x1, y1] = project(sampled[i]);
      const t = (valuesArr[i] - vMin) / (vMax - vMin || 1);
      ctx.strokeStyle = colorForValue(t);
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.lineTo(x1, y1);
      ctx.stroke();
    }
    const drawDot = (p, fill) => {
      const [x, y] = project(p);
      ctx.fillStyle = fill;
      ctx.beginPath();
      ctx.arc(x, y, 5, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = theme.bg;
      ctx.lineWidth = 2;
      ctx.stroke();
    };
    drawDot(sampled[0], "#22c55e");
    drawDot(sampled[sampled.length - 1], "#ef4444");
  }
  var renderWorkoutMap = (data, el, config, theme) => {
    var _a, _b, _c;
    el.addClass("health-md-workout-container");
    const picked = pickWorkout(data, config);
    if (!picked) {
      renderEmptyMessage(el, "No workout found");
      return;
    }
    const { day, workout } = picked;
    renderHeader(el, day, workout);
    const route = (_a = workout.route) != null ? _a : [];
    if (!route.length) {
      renderEmptyMessage(
        el,
        "Indoor workout \u2014 no GPS route available for this session."
      );
      return;
    }
    if (totalRouteDistance(route) < 5) {
      renderEmptyMessage(el, "GPS route is too short to display.");
      return;
    }
    const colorBy = String((_b = config.colorBy) != null ? _b : "speed").toLowerCase() === "hr" ? "hr" : "speed";
    const hrSamples = (_c = workout.timeSeries) == null ? void 0 : _c.heartRate;
    const widthCfg = typeof config.width === "number" ? config.width : 800;
    const heightCfg = typeof config.height === "number" ? config.height : 360;
    if (theme.mapTilesEnabled) {
      renderLeafletMap(el, route, colorBy, hrSamples, theme, heightCfg);
    } else {
      const renderedWidth = Math.round(el.clientWidth || widthCfg);
      const responsiveWidth = Math.min(widthCfg, Math.max(240, renderedWidth));
      renderCanvasPolyline(el, route, colorBy, hrSamples, theme, responsiveWidth, heightCfg);
    }
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/workout-intervals.ts
  function titleCase(value) {
    return value.split(/\s+/).filter(Boolean).map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(" ");
  }
  function renderEmptyMessage2(host, message) {
    const msg = host.createDiv({ cls: "health-md-workout-empty" });
    msg.textContent = message;
  }
  function renderHeader2(host, day, workout) {
    var _a, _b;
    const header = host.createDiv({ cls: "health-md-workout-header" });
    const title = header.createDiv({ cls: "health-md-workout-title" });
    title.textContent = `${titleCase((_a = workout.activityType) != null ? _a : workout.type)} \u2014 ${day.date}`;
    const stats = header.createDiv({ cls: "health-md-workout-stats" });
    const addStat2 = (label, value) => {
      if (!value) return;
      const cell = stats.createDiv({ cls: "health-md-workout-stat" });
      cell.createDiv({ cls: "health-md-workout-stat-label", text: label });
      cell.createDiv({ cls: "health-md-workout-stat-value", text: value });
    };
    addStat2("Duration", (_b = workout.durationFormatted) != null ? _b : formatDuration(workout.duration));
    addStat2("Distance", formatWorkoutDistance(workout, day));
    addStat2("Avg HR", workout.avgHeartRate != null ? `${Math.round(workout.avgHeartRate)} BPM` : void 0);
    addStat2("Avg Power", workout.avgPower != null ? `${Math.round(workout.avgPower)} W` : void 0);
  }
  function formatMaybeNumber(value, suffix) {
    return value == null ? "\u2014" : `${Math.round(value)} ${suffix}`;
  }
  function renderIntervalTable(host, label, rows) {
    host.createEl("h4", { text: label, cls: "health-md-workout-table-heading" });
    const wrapper = host.createDiv({ cls: "health-md-workout-table-wrap" });
    const table = wrapper.createEl("table", { cls: "health-md-workout-table" });
    const thead = table.createEl("thead");
    const headerRow = thead.createEl("tr");
    ["#", "Distance", "Time", "Pace / Speed", "Avg HR", "Max HR", "Avg Power", "Avg Cadence"].forEach((heading) => {
      headerRow.createEl("th", { text: heading });
    });
    const tbody = table.createEl("tbody");
    rows.forEach((row) => {
      var _a, _b, _c;
      const tr = tbody.createEl("tr");
      tr.createEl("td", { text: String(row.index) });
      tr.createEl("td", { text: (_a = row.distanceFormatted) != null ? _a : row.distance != null ? `${(row.distance / 1e3).toFixed(2)} km` : "\u2014" });
      tr.createEl("td", { text: row.duration ? formatDuration(row.duration) : "\u2014" });
      tr.createEl("td", { text: (_b = intervalRateDisplay(row)) != null ? _b : "\u2014" });
      tr.createEl("td", { text: formatMaybeNumber(row.avgHeartRate, "BPM") });
      tr.createEl("td", { text: formatMaybeNumber(row.maxHeartRate, "BPM") });
      tr.createEl("td", { text: formatMaybeNumber(row.avgPower, "W") });
      tr.createEl("td", { text: row.avgCadence == null ? "\u2014" : `${Math.round(row.avgCadence)} ${(_c = row.cadenceUnit) != null ? _c : ""}`.trim() });
    });
  }
  var renderWorkoutIntervals = (data, el, config, _theme) => {
    var _a, _b, _c, _d;
    el.addClass("health-md-workout-container");
    const picked = pickWorkout(data, config);
    if (!picked) {
      renderEmptyMessage2(el, "No workout found");
      return;
    }
    const { day, workout } = picked;
    renderHeader2(el, day, workout);
    const kind = String((_b = (_a = config.kind) != null ? _a : config.table) != null ? _b : "auto").trim().toLowerCase();
    const showLaps = kind === "auto" || kind === "laps" || kind === "lap";
    const showSplits = kind === "auto" || kind === "splits" || kind === "split";
    let rendered = false;
    if (showLaps && ((_c = workout.laps) == null ? void 0 : _c.length)) {
      renderIntervalTable(el, "Laps", workout.laps);
      rendered = true;
    }
    if (showSplits && ((_d = workout.splits) == null ? void 0 : _d.length)) {
      renderIntervalTable(el, "Splits", workout.splits);
      rendered = true;
    }
    if (!rendered) {
      renderEmptyMessage2(el, "No laps or splits were included for this workout.");
    }
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/mood-utils.ts
  var VALENCE_LABELS = [
    { max: -0.72, label: "Very unpleasant" },
    { max: -0.44, label: "Unpleasant" },
    { max: -0.16, label: "Slightly unpleasant" },
    { max: 0.16, label: "Neutral" },
    { max: 0.44, label: "Slightly pleasant" },
    { max: 0.72, label: "Pleasant" },
    { max: Infinity, label: "Very pleasant" }
  ];
  var LABEL_VALENCE = {
    "very unpleasant": -1,
    unpleasant: -0.67,
    "slightly unpleasant": -0.33,
    neutral: 0,
    "slightly pleasant": 0.33,
    pleasant: 0.67,
    "very pleasant": 1,
    amazed: 0.75,
    amused: 0.65,
    angry: -0.72,
    anxious: -0.62,
    ashamed: -0.72,
    brave: 0.35,
    calm: 0.55,
    content: 0.62,
    disappointed: -0.55,
    discouraged: -0.64,
    disgusted: -0.7,
    embarrassed: -0.55,
    excited: 0.78,
    frustrated: -0.65,
    grateful: 0.75,
    guilty: -0.62,
    happy: 0.82,
    hopeless: -0.9,
    irritated: -0.58,
    jealous: -0.55,
    joyful: 0.95,
    lonely: -0.72,
    passionate: 0.74,
    peaceful: 0.72,
    proud: 0.78,
    relieved: 0.55,
    sad: -0.82,
    scared: -0.78,
    stressed: -0.72,
    surprised: 0.1,
    worried: -0.65,
    annoyed: -0.5,
    confident: 0.7,
    drained: -0.55,
    hopeful: 0.65,
    indifferent: 0,
    overwhelmed: -0.68,
    satisfied: 0.7
  };
  function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function normalizeKey(value) {
    return value.trim().replace(/[_-]+/g, " ").replace(/\s+/g, " ").toLowerCase();
  }
  function clampValence(value) {
    return Math.max(-1, Math.min(1, value));
  }
  function parseNumber(value) {
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value !== "string") return void 0;
    const trimmed = value.trim();
    if (!trimmed) return void 0;
    const parsed = Number(trimmed.replace(/,/g, ""));
    return Number.isFinite(parsed) ? parsed : void 0;
  }
  function normalizeScore(value) {
    if (value >= 1 && value <= 5) return clampValence((value - 3) / 2);
    if (value >= 0 && value <= 10) return clampValence(value / 5 - 1);
    if (value >= 0 && value <= 100) return clampValence(value / 50 - 1);
    if (value >= -1 && value <= 1) return clampValence(value);
    return void 0;
  }
  function normalizeMoodValence(value, hint = "valence") {
    const numeric = parseNumber(value);
    if (numeric !== void 0) {
      if (hint === "score") return normalizeScore(numeric);
      if (numeric >= -1 && numeric <= 1) return clampValence(numeric);
      return normalizeScore(numeric);
    }
    if (typeof value !== "string") return void 0;
    const key = normalizeKey(value);
    return LABEL_VALENCE[key];
  }
  function moodLabelForValence(valence) {
    var _a, _b;
    if (valence === void 0 || !Number.isFinite(valence)) return "Unknown";
    const clamped = clampValence(valence);
    return (_b = (_a = VALENCE_LABELS.find((item) => clamped <= item.max)) == null ? void 0 : _a.label) != null ? _b : "Neutral";
  }
  function formatMoodValence(valence) {
    if (valence === void 0 || !Number.isFinite(valence)) return "\u2014";
    const clamped = clampValence(valence);
    return `${clamped >= 0 ? "+" : ""}${clamped.toFixed(2)}`;
  }
  function stringArrayFromUnknown(value) {
    if (Array.isArray(value)) {
      return value.map((item) => {
        if (typeof item === "string") return item.trim();
        if (typeof item === "number" || typeof item === "boolean" || typeof item === "bigint") return String(item);
        return "";
      }).filter(Boolean);
    }
    if (typeof value === "string") {
      return value.split(/[,;|]/g).map((item) => item.trim()).filter(Boolean);
    }
    return [];
  }
  function firstString(record, keys) {
    for (const key of keys) {
      const value = record[key];
      if (typeof value === "string" && value.trim()) return value.trim();
      if (typeof value === "number" || typeof value === "boolean" || typeof value === "bigint") return String(value);
    }
    return void 0;
  }
  function firstNumber(record, keys) {
    for (const key of keys) {
      const parsed = parseNumber(record[key]);
      if (parsed !== void 0) return parsed;
    }
    return void 0;
  }
  function normalizeTimestamp(raw, fallbackDate) {
    if (!raw) return fallbackDate;
    const value = raw.trim();
    if (!value) return fallbackDate;
    if (/^\d{1,2}:\d{2}(?::\d{2})?$/.test(value) && fallbackDate) {
      const [h = "0", m = "0", s = "0"] = value.split(":");
      return `${fallbackDate}T${h.padStart(2, "0")}:${m.padStart(2, "0")}:${s.padStart(2, "0")}`;
    }
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return `${value}T12:00:00`;
    return value;
  }
  function moodEntryFromRecord(record, fallbackDate) {
    var _a, _b, _c, _d;
    const valenceRaw = firstNumber(record, [
      "valence",
      "moodValence",
      "mood_valence",
      "stateOfMindValence",
      "state_of_mind_valence",
      "averageValence",
      "average_valence",
      "avgValence",
      "avg_valence"
    ]);
    const scoreRaw = firstNumber(record, [
      "score",
      "moodScore",
      "mood_score",
      "rating",
      "moodRating",
      "mood_rating",
      "valencePercent",
      "valence_percent",
      "moodPercent",
      "mood_percent",
      "averageValencePercent",
      "average_valence_percent",
      "averageMoodPercent",
      "average_mood_percent"
    ]);
    const label = firstString(record, [
      "label",
      "primaryLabel",
      "primary_label",
      "moodLabel",
      "mood_label",
      "state"
    ]);
    const valenceDescription = firstString(record, [
      "classification",
      "valenceClassification",
      "valence_classification",
      "valenceDescription",
      "valence_description",
      "feeling"
    ]);
    const rawMood = record.mood;
    const moodLabel = typeof rawMood === "string" && rawMood.trim() ? rawMood.trim() : void 0;
    const labels = [
      ...stringArrayFromUnknown(record.labels),
      ...stringArrayFromUnknown(record.emotions),
      ...stringArrayFromUnknown(record.feelings)
    ].filter((item, index, all) => all.indexOf(item) === index);
    const primaryLabel2 = (_b = (_a = label != null ? label : moodLabel) != null ? _a : labels[0]) != null ? _b : valenceDescription;
    const valence = (_d = (_c = normalizeMoodValence(valenceRaw, "valence")) != null ? _c : normalizeMoodValence(scoreRaw, "score")) != null ? _d : normalizeMoodValence(primaryLabel2, "label");
    const timestamp = normalizeTimestamp(firstString(record, [
      "timestamp",
      "date",
      "recordedAt",
      "recorded_at",
      "startDate",
      "start_date",
      "startTime",
      "start_time",
      "time"
    ]), fallbackDate);
    const endDate = normalizeTimestamp(firstString(record, ["endDate", "end_date", "endTime", "end_time"]), fallbackDate);
    const kind = firstString(record, ["kind", "moodKind", "mood_kind", "feelingKind", "feeling_kind", "category"]);
    const associations = [
      ...stringArrayFromUnknown(record.associations),
      ...stringArrayFromUnknown(record.contexts),
      ...stringArrayFromUnknown(record.factors)
    ].filter((item, index, all) => all.indexOf(item) === index);
    if (valence === void 0 && !primaryLabel2 && !labels.length && !kind) return null;
    return {
      timestamp,
      startDate: timestamp,
      endDate,
      kind,
      valence,
      score: scoreRaw,
      label: primaryLabel2,
      labels: labels.length ? labels : void 0,
      associations: associations.length ? associations : void 0
    };
  }
  function primitiveMoodEntry(value, fallbackDate) {
    const valence = normalizeMoodValence(value, typeof value === "number" ? "valence" : "label");
    const label = typeof value === "string" && value.trim() ? value.trim() : void 0;
    if (valence === void 0 && !label) return null;
    return {
      timestamp: fallbackDate ? `${fallbackDate}T12:00:00` : void 0,
      startDate: fallbackDate ? `${fallbackDate}T12:00:00` : void 0,
      valence,
      label
    };
  }
  function moodEntriesFromArray(values, fallbackDate) {
    const entries = [];
    for (const item of values) {
      entries.push(...moodEntriesFromUnknown(item, fallbackDate));
    }
    return entries;
  }
  function moodEntriesFromUnknown(value, fallbackDate) {
    if (value === void 0 || value === null || value === "") return [];
    if (Array.isArray(value)) return moodEntriesFromArray(value, fallbackDate);
    if (!isRecord(value)) {
      const entry = primitiveMoodEntry(value, fallbackDate);
      return entry ? [entry] : [];
    }
    const entries = [];
    for (const key of ["entries", "samples", "records", "states", "stateOfMind", "state_of_mind", "stateOfMindEntries", "state_of_mind_entries", "moods"]) {
      const nested = value[key];
      if (Array.isArray(nested)) entries.push(...moodEntriesFromArray(nested, fallbackDate));
    }
    if (!entries.length) {
      const ownEntry = moodEntryFromRecord(value, fallbackDate);
      if (ownEntry) entries.push(ownEntry);
    }
    return dedupeMoodEntries(entries);
  }
  function dedupeMoodEntries(entries) {
    var _a, _b, _c, _d, _e, _f;
    const seen = /* @__PURE__ */ new Set();
    const deduped = [];
    for (const entry of entries) {
      const key = [
        (_b = (_a = entry.timestamp) != null ? _a : entry.startDate) != null ? _b : "",
        (_c = entry.kind) != null ? _c : "",
        (_d = entry.valence) != null ? _d : "",
        (_e = entry.label) != null ? _e : "",
        ((_f = entry.labels) != null ? _f : []).join("|")
      ].join("~");
      if (seen.has(key)) continue;
      seen.add(key);
      deduped.push(entry);
    }
    return deduped.sort((a, b) => {
      var _a2, _b2, _c2, _d2;
      return ((_b2 = (_a2 = a.timestamp) != null ? _a2 : a.startDate) != null ? _b2 : "").localeCompare((_d2 = (_c2 = b.timestamp) != null ? _c2 : b.startDate) != null ? _d2 : "");
    });
  }
  function primaryLabel(entries, averageValence) {
    var _a, _b;
    const counts = /* @__PURE__ */ new Map();
    for (const entry of entries) {
      const labels = ((_a = entry.labels) == null ? void 0 : _a.length) ? entry.labels : entry.label ? [entry.label] : [];
      for (const label of labels) counts.set(label, ((_b = counts.get(label)) != null ? _b : 0) + 1);
    }
    let best;
    let bestCount = 0;
    for (const [label, count] of counts) {
      if (count > bestCount) {
        best = label;
        bestCount = count;
      }
    }
    return best != null ? best : averageValence !== void 0 ? moodLabelForValence(averageValence) : void 0;
  }
  function createMoodSummary(entries) {
    const normalized = dedupeMoodEntries(entries).filter(
      (entry) => {
        var _a;
        return entry.valence !== void 0 || entry.label || ((_a = entry.labels) == null ? void 0 : _a.length) || entry.kind;
      }
    );
    if (!normalized.length) return void 0;
    const values = normalized.map((entry) => entry.valence).filter((value) => value !== void 0 && Number.isFinite(value));
    const averageValence = values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : void 0;
    return {
      entries: normalized,
      averageValence,
      minValence: values.length ? Math.min(...values) : void 0,
      maxValence: values.length ? Math.max(...values) : void 0,
      primaryLabel: primaryLabel(normalized, averageValence)
    };
  }
  function getMoodDaySummary(day) {
    const dayRecord = day;
    const entries = dedupeMoodEntries([
      ...moodEntriesFromUnknown(dayRecord.mood, day.date),
      ...moodEntriesFromUnknown(dayRecord.stateOfMind, day.date),
      ...moodEntriesFromUnknown(dayRecord.state_of_mind, day.date),
      ...moodEntriesFromUnknown(dayRecord.moods, day.date),
      ...moodEntriesFromUnknown(dayRecord.mindfulness, day.date)
    ]);
    const summary = createMoodSummary(entries);
    return {
      date: day.date,
      entries,
      averageValence: summary == null ? void 0 : summary.averageValence,
      minValence: summary == null ? void 0 : summary.minValence,
      maxValence: summary == null ? void 0 : summary.maxValence,
      primaryLabel: summary == null ? void 0 : summary.primaryLabel
    };
  }

  // ../../obsidian-plugin-hub/obsidian-health-md/src/mood-viz-utils.ts
  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }
  function configFlag(value, defaultValue) {
    if (value === void 0) return defaultValue;
    if (typeof value === "number") return value !== 0;
    const normalized = value.trim().toLowerCase();
    if (["false", "0", "no", "off"].includes(normalized)) return false;
    if (["true", "1", "yes", "on"].includes(normalized)) return true;
    return defaultValue;
  }
  function configNumber(value, fallback) {
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value === "string" && value.trim()) {
      const parsed = Number(value.trim());
      if (Number.isFinite(parsed)) return parsed;
    }
    return fallback;
  }
  function configString(value, fallback) {
    return typeof value === "string" && value.trim() ? value.trim() : fallback;
  }
  function average(values) {
    const finite = values.filter(Number.isFinite);
    return finite.length ? finite.reduce((sum, value) => sum + value, 0) / finite.length : void 0;
  }
  function moodHex(valence, theme) {
    if (valence === void 0 || !Number.isFinite(valence)) return theme.muted;
    if (valence < -0.16) return theme.colors.heart;
    if (valence > 0.16) return theme.colors.accent;
    return theme.colors.secondary;
  }
  function moodRgba(valence, theme, alpha = 0.75) {
    return hexToRgba(moodHex(valence, theme), alpha);
  }
  function yForValence(valence, top, height) {
    return top + (1 - (clamp(valence, -1, 1) + 1) / 2) * height;
  }
  function valencePercent(valence) {
    if (valence === void 0 || !Number.isFinite(valence)) return "\u2014";
    return `${Math.round((clamp(valence, -1, 1) + 1) / 2 * 100)}%`;
  }
  function dayExerciseMinutes(day) {
    var _a, _b, _c;
    const activityMinutes = (_b = (_a = day.activity) == null ? void 0 : _a.exerciseMinutes) != null ? _b : 0;
    const workoutMinutes = ((_c = day.workouts) != null ? _c : []).reduce((sum, workout) => sum + (workout.duration || 0) / 60, 0);
    return Math.max(activityMinutes, workoutMinutes);
  }
  function shortDate(iso) {
    const d = /* @__PURE__ */ new Date(iso + "T00:00:00");
    return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  }
  function parseHour(timestamp, fallbackDate) {
    var _a;
    if (!timestamp) return void 0;
    const trimmed = timestamp.trim();
    const timeOnly = /^(\d{1,2}):(\d{2})(?::(\d{2}))?/.exec(trimmed);
    const dateTime = /T(\d{1,2}):(\d{2})(?::(\d{2}))?/.exec(trimmed);
    const match = dateTime != null ? dateTime : timeOnly;
    if (!match) {
      if (fallbackDate && trimmed === fallbackDate) return 12;
      return void 0;
    }
    const h = Number(match[1]);
    const m = Number(match[2]);
    const s = Number((_a = match[3]) != null ? _a : 0);
    if (h > 23 || m > 59 || s > 59) return void 0;
    return h + m / 60 + s / 3600;
  }
  function normalizeKind(kind) {
    const normalized = (kind != null ? kind : "").replace(/[_-]+/g, " ").toLowerCase();
    if (normalized.includes("daily")) return "daily";
    if (normalized.includes("momentary") || normalized.includes("emotion")) return "momentary";
    return "other";
  }
  function kindLabel(kind) {
    switch (normalizeKind(kind)) {
      case "daily":
        return "Daily Mood";
      case "momentary":
        return "Momentary Emotion";
      default:
        return kind || "Mood";
    }
  }
  function entryLabels(entry) {
    var _a;
    const labels = ((_a = entry.labels) == null ? void 0 : _a.length) ? entry.labels : entry.label ? [entry.label] : [];
    return labels.filter((item, index, all) => Boolean(item) && all.indexOf(item) === index);
  }
  function collectMoodDays(data) {
    return data.map((day) => {
      var _a, _b;
      const mood = getMoodDaySummary(day);
      return {
        day,
        date: day.date,
        entries: mood.entries,
        averageValence: mood.averageValence,
        minValence: mood.minValence,
        maxValence: mood.maxValence,
        primaryLabel: mood.primaryLabel,
        sleepSeconds: (_a = day.sleep) == null ? void 0 : _a.totalDuration,
        exerciseMinutes: dayExerciseMinutes(day),
        hrv: (_b = day.heart) == null ? void 0 : _b.hrv
      };
    }).sort((a, b) => a.date.localeCompare(b.date));
  }
  function collectMoodEntries(data) {
    return collectMoodDays(data).flatMap((moodDay) => moodDay.entries.map((entry) => {
      var _a, _b, _c, _d;
      return {
        day: moodDay.day,
        date: moodDay.date,
        entry,
        timestamp: (_a = entry.timestamp) != null ? _a : entry.startDate,
        hour: parseHour((_b = entry.timestamp) != null ? _b : entry.startDate, moodDay.date),
        valence: entry.valence,
        label: (_c = entry.label) != null ? _c : entryLabels(entry)[0],
        labels: entryLabels(entry),
        associations: (_d = entry.associations) != null ? _d : [],
        kind: entry.kind
      };
    })).sort((a, b) => {
      var _a, _b;
      return a.date === b.date ? ((_a = a.hour) != null ? _a : 12) - ((_b = b.hour) != null ? _b : 12) : a.date.localeCompare(b.date);
    });
  }
  function moodDaysWithValues(data) {
    return collectMoodDays(data).filter((day) => day.averageValence !== void 0);
  }
  function emptyState(ctx, W, H, theme, statsEl, text = "No mood data in range") {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    ctx.fillStyle = theme.muted;
    ctx.font = "12px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(text, W / 2, H / 2);
    statsEl.empty();
  }
  function drawTitle(ctx, theme, title, subtitle, x = 18, y = 24) {
    ctx.textAlign = "left";
    ctx.textBaseline = "alphabetic";
    ctx.fillStyle = theme.fg;
    ctx.font = "600 20px sans-serif";
    ctx.fillText(title, x, y);
    ctx.fillStyle = theme.muted;
    ctx.font = "11px sans-serif";
    ctx.fillText(subtitle, x, y + 17);
  }
  function drawValenceGrid(ctx, theme, x, y, w, h) {
    for (const tick of [
      { value: 1, label: "+1" },
      { value: 0, label: "0" },
      { value: -1, label: "-1" }
    ]) {
      const ty = yForValence(tick.value, y, h);
      ctx.strokeStyle = tick.value === 0 ? hexToRgba(theme.fg, 0.18) : hexToRgba(theme.fg, 0.08);
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x, ty);
      ctx.lineTo(x + w, ty);
      ctx.stroke();
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      ctx.fillText(tick.label, x - 6, ty);
    }
  }
  function dateToUtc(iso) {
    return /* @__PURE__ */ new Date(iso + "T00:00:00Z");
  }
  function isoDate(date) {
    return date.toISOString().slice(0, 10);
  }
  function addDays(iso, days) {
    const d = dateToUtc(iso);
    d.setUTCDate(d.getUTCDate() + days);
    return isoDate(d);
  }
  function aggregate(values) {
    var _a;
    const buckets = /* @__PURE__ */ new Map();
    for (const value of values) {
      const key = value.key || "Unspecified";
      const existing = (_a = buckets.get(key)) != null ? _a : { key, count: 0, sum: 0, values: [] };
      existing.count += 1;
      if (value.valence !== void 0 && Number.isFinite(value.valence)) {
        existing.sum += value.valence;
        existing.values.push(value.valence);
      }
      buckets.set(key, existing);
    }
    return Array.from(buckets.values());
  }
  function bucketAverage(bucket) {
    return bucket.values.length ? bucket.sum / bucket.values.length : void 0;
  }
  function detailsForEntry(entry) {
    var _a;
    return [
      { label: "Mood", value: entry.valence !== void 0 ? `${moodLabelForValence(entry.valence)} (${formatMoodValence(entry.valence)})` : (_a = entry.label) != null ? _a : "Mood" },
      { label: "Kind", value: kindLabel(entry.kind) },
      ...entry.labels.length ? [{ label: "Labels", value: entry.labels.join(", ") }] : [],
      ...entry.associations.length ? [{ label: "Associations", value: entry.associations.join(", ") }] : []
    ];
  }

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/mood-trend.ts
  var renderMoodTrend = (ctx, data, W, H, config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const points = collectMoodDays(data).map((day) => ({
      day: day.day,
      date: day.date,
      valence: day.averageValence,
      label: day.primaryLabel,
      entries: day.entries.length
    }));
    const moodPoints = points.filter((point) => point.valence !== void 0);
    if (!points.length || !moodPoints.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText("No mood data in range", W / 2, H / 2);
      statsEl.empty();
      return;
    }
    const showContext = configFlag(config.showContext, true);
    const padL = 54;
    const padR = 16;
    const padT = showContext ? 72 : 56;
    const padB = 34;
    const plotW2 = W - padL - padR;
    const plotH = H - padT - padB;
    const slot = plotW2 / Math.max(points.length, 1);
    const values = moodPoints.map((point) => point.valence).filter(Number.isFinite);
    const avg3 = values.reduce((sum, value) => sum + value, 0) / values.length;
    const firstDate = points[0].date;
    const lastDate = points[points.length - 1].date;
    ctx.textAlign = "left";
    ctx.textBaseline = "alphabetic";
    ctx.fillStyle = theme.fg;
    ctx.font = "600 22px sans-serif";
    ctx.fillText(moodLabelForValence(avg3), padL, 24);
    ctx.fillStyle = theme.muted;
    ctx.font = "11px sans-serif";
    ctx.fillText(`${formatMoodValence(avg3)} avg \u2022 ${formatDate(firstDate)} \u2013 ${formatDate(lastDate)}`, padL, 41);
    const ticks = [
      { value: 1, label: "pleasant" },
      { value: 0, label: "neutral" },
      { value: -1, label: "unpleasant" }
    ];
    ctx.lineWidth = 1;
    for (const tick of ticks) {
      const y = yForValence(tick.value, padT, plotH);
      ctx.strokeStyle = tick.value === 0 ? hexToRgba(theme.fg, 0.18) : hexToRgba(theme.fg, 0.08);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      ctx.fillText(tick.label, padL - 6, y);
    }
    if (showContext) {
      const maxExercise = Math.max(30, ...points.map((point) => dayExerciseMinutes(point.day)));
      points.forEach((point, i) => {
        var _a, _b;
        const cx = padL + i * slot + slot / 2;
        const colW = Math.max(2, Math.min(18, slot * 0.42));
        const sleepHours = ((_b = (_a = point.day.sleep) == null ? void 0 : _a.totalDuration) != null ? _b : 0) / 3600;
        if (sleepHours > 0) {
          const sleepH = clamp(sleepHours / 10, 0, 1) * plotH;
          ctx.fillStyle = hexToRgba(theme.colors.sleep.core, 0.16);
          ctx.beginPath();
          ctx.roundRect(cx - colW / 2, padT + plotH - sleepH, colW, sleepH, [3, 3, 0, 0]);
          ctx.fill();
        }
        const exercise = dayExerciseMinutes(point.day);
        if (exercise > 0) {
          const exerciseH = clamp(exercise / maxExercise, 0, 1) * plotH;
          ctx.fillStyle = hexToRgba(theme.colors.secondary, 0.14);
          ctx.beginPath();
          ctx.roundRect(cx - colW / 4, padT + plotH - exerciseH, colW / 2, exerciseH, [2, 2, 0, 0]);
          ctx.fill();
        }
      });
      ctx.font = "9px sans-serif";
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      let lx = padL;
      for (const item of [
        { label: "sleep", color: theme.colors.sleep.core },
        { label: "exercise", color: theme.colors.secondary }
      ]) {
        ctx.fillStyle = hexToRgba(item.color, 0.45);
        ctx.fillRect(lx, padT - 16, 9, 6);
        ctx.fillStyle = theme.muted;
        ctx.fillText(item.label, lx + 12, padT - 12);
        lx += 62;
      }
    }
    ctx.save();
    ctx.lineWidth = 2;
    ctx.strokeStyle = hexToRgba(theme.colors.accent, 0.7);
    ctx.beginPath();
    let activeSegment = false;
    points.forEach((point, i) => {
      if (point.valence === void 0) {
        activeSegment = false;
        return;
      }
      const x = padL + i * slot + slot / 2;
      const y = yForValence(point.valence, padT, plotH);
      if (!activeSegment) {
        ctx.moveTo(x, y);
        activeSegment = true;
      } else {
        ctx.lineTo(x, y);
      }
    });
    ctx.stroke();
    ctx.restore();
    points.forEach((point, i) => {
      var _a, _b;
      const cx = padL + i * slot + slot / 2;
      const hitX = padL + i * slot;
      const moodY = point.valence !== void 0 ? yForValence(point.valence, padT, plotH) : yForValence(0, padT, plotH);
      const color = moodHex(point.valence, theme);
      if (point.valence === void 0) {
        ctx.fillStyle = hexToRgba(theme.fg, 0.16);
        ctx.beginPath();
        ctx.arc(cx, moodY, 2.2, 0, Math.PI * 2);
        ctx.fill();
      } else {
        const r = point.entries > 1 ? 6 : 5;
        ctx.fillStyle = hexToRgba(color, 0.18);
        ctx.beginPath();
        ctx.arc(cx, moodY, r + 5, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(cx, moodY, r, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = theme.bg;
        ctx.lineWidth = 1.5;
        ctx.stroke();
      }
      if (points.length <= 14 || i % Math.ceil(points.length / 6) === 0 || i === points.length - 1) {
        ctx.fillStyle = point.valence !== void 0 ? theme.fg : theme.muted;
        ctx.font = "9px sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "top";
        ctx.fillText(shortDate(point.date), cx, padT + plotH + 8);
      }
      const sleepSeconds = (_a = point.day.sleep) == null ? void 0 : _a.totalDuration;
      const exerciseMinutes = dayExerciseMinutes(point.day);
      const details = [
        ...point.valence !== void 0 ? [{ label: "Mood", value: `${moodLabelForValence(point.valence)} (${formatMoodValence(point.valence)})` }] : [],
        ...point.label ? [{ label: "Label", value: point.label }] : [],
        ...point.entries ? [{ label: "Entries", value: String(point.entries) }] : [],
        ...sleepSeconds ? [{ label: "Sleep", value: formatDuration(sleepSeconds) }] : [],
        ...exerciseMinutes ? [{ label: "Exercise", value: `${Math.round(exerciseMinutes)} min` }] : [],
        ...((_b = point.day.workouts) == null ? void 0 : _b.length) ? [{ label: "Workouts", value: String(point.day.workouts.length) }] : []
      ];
      hits.add({
        shape: "rect",
        x: hitX,
        y: padT,
        w: slot,
        h: plotH + padB,
        title: formatDate(point.date),
        details,
        payload: point.day
      });
    });
    const totalEntries = moodPoints.reduce((sum, point) => sum + point.entries, 0);
    const avgSleepSeconds = moodPoints.reduce((sum, point) => {
      var _a, _b;
      return sum + ((_b = (_a = point.day.sleep) == null ? void 0 : _a.totalDuration) != null ? _b : 0);
    }, 0) / moodPoints.length;
    const avgExercise = moodPoints.reduce((sum, point) => sum + dayExerciseMinutes(point.day), 0) / moodPoints.length;
    renderInlineStats(statsEl, [
      [
        { text: "Avg mood " },
        { text: `${moodLabelForValence(avg3)} ${formatMoodValence(avg3)}`, strong: true }
      ],
      [
        { text: "Mood entries " },
        { text: String(totalEntries), strong: true }
      ],
      ...avgSleepSeconds > 0 ? [[
        { text: "Avg sleep " },
        { text: formatDuration(avgSleepSeconds), strong: true }
      ]] : [],
      ...avgExercise > 0 ? [[
        { text: "Avg exercise " },
        { text: `${Math.round(avgExercise)}m`, strong: true }
      ]] : []
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/mood-insights.ts
  var renderMoodCalendarHeatmap = (ctx, data, W, H, config, theme, statsEl, hits) => {
    var _a;
    const days = moodDaysWithValues(data);
    if (!days.length) return emptyState(ctx, W, H, theme, statsEl);
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const first = days[0].date;
    const last = days[days.length - 1].date;
    const start = dateToUtc(first);
    start.setUTCDate(start.getUTCDate() - start.getUTCDay());
    const end = dateToUtc(last);
    end.setUTCDate(end.getUTCDate() + (6 - end.getUTCDay()));
    const totalDays = Math.round((end.getTime() - start.getTime()) / 864e5) + 1;
    const weeks = Math.ceil(totalDays / 7);
    const padL = 44;
    const padR = 18;
    const padT = 58;
    const padB = 24;
    const slotW = (W - padL - padR) / weeks;
    const slotH = (H - padT - padB) / 7;
    const cell = Math.max(3, Math.min(slotW, slotH) - 3);
    const byDate = new Map(days.map((day) => [day.date, day]));
    const avg3 = (_a = average(days.map((day) => day.averageValence).filter(Number.isFinite))) != null ? _a : 0;
    drawTitle(ctx, theme, "Mood calendar", `${formatDate(first)} \u2013 ${formatDate(last)} \u2022 ${days.length} logged days`);
    ctx.font = "10px sans-serif";
    ctx.fillStyle = theme.muted;
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";
    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].forEach((label, i) => ctx.fillText(label, padL - 8, padT + i * slotH + slotH / 2));
    let previousMonth = "";
    for (let i = 0; i < totalDays; i++) {
      const date = addDays(isoDate(start), i);
      const d = dateToUtc(date);
      const week = Math.floor(i / 7);
      const dow = d.getUTCDay();
      const x = padL + week * slotW + (slotW - cell) / 2;
      const y = padT + dow * slotH + (slotH - cell) / 2;
      const moodDay = byDate.get(date);
      ctx.fillStyle = moodDay ? moodRgba(moodDay.averageValence, theme, 0.72) : hexToRgba(theme.fg, 0.05);
      ctx.beginPath();
      ctx.roundRect(x, y, cell, cell, 3);
      ctx.fill();
      if (!moodDay) {
        ctx.strokeStyle = hexToRgba(theme.fg, 0.05);
        ctx.stroke();
      }
      if (moodDay) {
        hits.add({
          shape: "rect",
          x,
          y,
          w: cell,
          h: cell,
          title: formatDate(date),
          details: [
            { label: "Mood", value: `${moodLabelForValence(moodDay.averageValence)} (${formatMoodValence(moodDay.averageValence)})` },
            { label: "Entries", value: String(moodDay.entries.length) },
            ...moodDay.sleepSeconds ? [{ label: "Sleep", value: formatDuration(moodDay.sleepSeconds) }] : []
          ],
          payload: moodDay.day
        });
      }
      const month = d.toLocaleDateString("en-US", { month: "short", timeZone: "UTC" });
      if (dow === 0 && month !== previousMonth) {
        ctx.fillStyle = theme.muted;
        ctx.font = "9px sans-serif";
        ctx.textAlign = "left";
        ctx.fillText(month, x, padT - 8);
        previousMonth = month;
      }
    }
    renderInlineStats(statsEl, [[{ text: "Avg mood " }, { text: `${moodLabelForValence(avg3)} ${formatMoodValence(avg3)}`, strong: true }], [{ text: "Mood entries " }, { text: String(days.reduce((sum, day) => sum + day.entries.length, 0)), strong: true }]]);
  };
  var renderMoodSleepScatter = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    var _a, _b, _c, _d;
    const days = moodDaysWithValues(data).filter((day) => {
      var _a2;
      return ((_a2 = day.sleepSeconds) != null ? _a2 : 0) > 0;
    });
    if (!days.length) return emptyState(ctx, W, H, theme, statsEl, "No mood + sleep data in range");
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const padL = 52, padR = 18, padT = 58, padB = 42;
    const plotW2 = W - padL - padR;
    const plotH = H - padT - padB;
    const sleepHours = days.map((day) => {
      var _a2;
      return ((_a2 = day.sleepSeconds) != null ? _a2 : 0) / 3600;
    });
    const maxSleep = Math.max(9, Math.ceil(Math.max(...sleepHours)));
    const avgMood = (_a = average(days.map((day) => day.averageValence))) != null ? _a : 0;
    drawTitle(ctx, theme, "Mood \xD7 sleep", `${days.length} days \u2022 color = mood, ring = exercise`);
    drawValenceGrid(ctx, theme, padL, padT, plotW2, plotH);
    ctx.strokeStyle = hexToRgba(theme.fg, 0.18);
    ctx.beginPath();
    ctx.moveTo(padL, padT + plotH);
    ctx.lineTo(padL + plotW2, padT + plotH);
    ctx.stroke();
    for (let h = 0; h <= maxSleep; h += 2) {
      const x = padL + h / maxSleep * plotW2;
      ctx.strokeStyle = hexToRgba(theme.fg, 0.06);
      ctx.beginPath();
      ctx.moveTo(x, padT);
      ctx.lineTo(x, padT + plotH);
      ctx.stroke();
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "top";
      ctx.fillText(`${h}h`, x, padT + plotH + 8);
    }
    for (const day of days) {
      const x = padL + ((_b = day.sleepSeconds) != null ? _b : 0) / 3600 / maxSleep * plotW2;
      const y = yForValence(day.averageValence, padT, plotH);
      const r = clamp(4 + day.entries.length * 1.2, 4, 9);
      if (day.exerciseMinutes > 0) {
        ctx.strokeStyle = hexToRgba(theme.colors.secondary, clamp(day.exerciseMinutes / 80, 0.25, 0.8));
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(x, y, r + 4, 0, Math.PI * 2);
        ctx.stroke();
      }
      ctx.fillStyle = moodRgba(day.averageValence, theme, 0.85);
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
      hits.add({
        shape: "circle",
        cx: x,
        cy: y,
        r: r + 6,
        title: formatDate(day.date),
        details: [
          { label: "Mood", value: `${moodLabelForValence(day.averageValence)} (${formatMoodValence(day.averageValence)})` },
          { label: "Sleep", value: formatDuration((_c = day.sleepSeconds) != null ? _c : 0) },
          { label: "Exercise", value: `${Math.round(day.exerciseMinutes)} min` },
          { label: "Entries", value: String(day.entries.length) }
        ],
        payload: day.day
      });
    }
    renderInlineStats(statsEl, [[{ text: "Avg mood " }, { text: `${moodLabelForValence(avgMood)} ${formatMoodValence(avgMood)}`, strong: true }], [{ text: "Avg sleep " }, { text: formatDuration((_d = average(days.map((day) => {
      var _a2;
      return (_a2 = day.sleepSeconds) != null ? _a2 : 0;
    }))) != null ? _d : 0), strong: true }]]);
  };
  var renderMoodDayTimeline = (ctx, data, W, H, config, theme, statsEl, hits) => {
    const maxDays = Math.max(1, Math.floor(configNumber(config.maxDays, 21)));
    const days = collectMoodDays(data).filter((day) => day.entries.length).slice(-maxDays);
    const entries = days.flatMap((day) => day.entries);
    if (!entries.length) return emptyState(ctx, W, H, theme, statsEl);
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const padL = 72, padR = 18, padT = 58, padB = 30;
    const plotW2 = W - padL - padR;
    const rowH = (H - padT - padB) / days.length;
    drawTitle(ctx, theme, "Mood day timeline", `${days.length} days \u2022 entries placed by time of day`);
    for (const hour of [0, 6, 12, 18, 24]) {
      const x = padL + hour / 24 * plotW2;
      ctx.strokeStyle = hexToRgba(theme.fg, hour === 12 ? 0.16 : 0.08);
      ctx.beginPath();
      ctx.moveTo(x, padT);
      ctx.lineTo(x, H - padB);
      ctx.stroke();
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "top";
      ctx.fillText(hour === 24 ? "24" : `${hour}:00`, x, H - padB + 8);
    }
    days.forEach((day, row) => {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j;
      const y = padT + row * rowH + rowH / 2;
      ctx.strokeStyle = hexToRgba(theme.fg, 0.08);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(padL + plotW2, y);
      ctx.stroke();
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      ctx.fillText(shortDate(day.date), padL - 8, y);
      const bedtime = parseHour((_c = (_a = day.day.sleep) == null ? void 0 : _a.bedtime) != null ? _c : (_b = day.day.sleep) == null ? void 0 : _b.bedtimeISO, day.date);
      const wake = parseHour((_f = (_d = day.day.sleep) == null ? void 0 : _d.wakeTime) != null ? _f : (_e = day.day.sleep) == null ? void 0 : _e.wakeTimeISO, day.date);
      if (bedtime !== void 0 && wake !== void 0) {
        const drawSpan = (start, end) => {
          const x = padL + start / 24 * plotW2;
          const w = Math.max(1, (end - start) / 24 * plotW2);
          ctx.fillStyle = hexToRgba(theme.colors.sleep.core, 0.14);
          ctx.fillRect(x, y - Math.max(2, rowH * 0.18), w, Math.max(4, rowH * 0.36));
        };
        if (bedtime <= wake) drawSpan(bedtime, wake);
        else {
          drawSpan(bedtime, 24);
          drawSpan(0, wake);
        }
      }
      for (const entry of day.entries) {
        const hour = (_h = parseHour((_g = entry.timestamp) != null ? _g : entry.startDate, day.date)) != null ? _h : 12;
        const x = padL + hour / 24 * plotW2;
        const valence = entry.valence;
        const offset = valence !== void 0 ? -valence * Math.min(rowH * 0.28, 8) : 0;
        ctx.fillStyle = moodRgba(valence, theme, 0.85);
        ctx.beginPath();
        ctx.arc(x, y + offset, 5, 0, Math.PI * 2);
        ctx.fill();
        hits.add({
          shape: "circle",
          cx: x,
          cy: y + offset,
          r: 8,
          title: `${formatDate(day.date)} ${(_i = entry.timestamp) != null ? _i : ""}`,
          details: detailsForEntry({ day: day.day, date: day.date, entry, timestamp: entry.timestamp, hour, valence, label: entry.label, labels: entryLabels(entry), associations: (_j = entry.associations) != null ? _j : [], kind: entry.kind }),
          payload: day.day
        });
      }
    });
    renderInlineStats(statsEl, [[{ text: "Entries " }, { text: String(entries.length), strong: true }], [{ text: "Days " }, { text: String(days.length), strong: true }]]);
  };
  var renderMoodAssociationBreakdown = (ctx, data, W, H, config, theme, statsEl, hits) => {
    var _a;
    const entries = collectMoodEntries(data).filter((entry) => entry.valence !== void 0);
    if (!entries.length) return emptyState(ctx, W, H, theme, statsEl);
    const limit = Math.max(3, Math.floor(configNumber(config.limit, 10)));
    const sort = configString(config.sort, "count");
    const buckets = aggregate(entries.flatMap((entry) => (entry.associations.length ? entry.associations : ["Unspecified"]).map((key) => ({ key, valence: entry.valence }))));
    buckets.sort((a, b) => {
      var _a2, _b;
      return sort === "valence" ? ((_a2 = bucketAverage(b)) != null ? _a2 : 0) - ((_b = bucketAverage(a)) != null ? _b : 0) : b.count - a.count;
    });
    const shown = buckets.slice(0, limit);
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const padL = 120, padR = 26, padT = 60, padB = 24;
    const plotW2 = W - padL - padR;
    const rowH = (H - padT - padB) / shown.length;
    const mid = padL + plotW2 / 2;
    drawTitle(ctx, theme, "Mood by association", `${shown.length} associations \u2022 centered at neutral`);
    ctx.strokeStyle = hexToRgba(theme.fg, 0.18);
    ctx.beginPath();
    ctx.moveTo(mid, padT - 6);
    ctx.lineTo(mid, H - padB);
    ctx.stroke();
    shown.forEach((bucket, i) => {
      var _a2;
      const avg3 = (_a2 = bucketAverage(bucket)) != null ? _a2 : 0;
      const y = padT + i * rowH + rowH / 2;
      const barW = Math.abs(avg3) * (plotW2 / 2);
      const x = avg3 >= 0 ? mid : mid - barW;
      ctx.fillStyle = moodRgba(avg3, theme, 0.75);
      ctx.beginPath();
      ctx.roundRect(x, y - rowH * 0.25, barW, Math.max(4, rowH * 0.5), 4);
      ctx.fill();
      ctx.fillStyle = theme.fg;
      ctx.font = "11px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      ctx.fillText(bucket.key, padL - 10, y);
      ctx.textAlign = avg3 >= 0 ? "left" : "right";
      ctx.fillStyle = theme.muted;
      ctx.fillText(`${formatMoodValence(avg3)} \u2022 ${bucket.count}`, avg3 >= 0 ? x + barW + 6 : x - 6, y);
      hits.add({ shape: "rect", x: padL, y: y - rowH / 2, w: plotW2, h: rowH, title: bucket.key, details: [{ label: "Avg mood", value: `${moodLabelForValence(avg3)} (${formatMoodValence(avg3)})` }, { label: "Entries", value: String(bucket.count) }] });
    });
    const avgAll = (_a = average(entries.map((entry) => entry.valence).filter(Number.isFinite))) != null ? _a : 0;
    renderInlineStats(statsEl, [[{ text: "Avg mood " }, { text: `${moodLabelForValence(avgAll)} ${formatMoodValence(avgAll)}`, strong: true }], [{ text: "Associations " }, { text: String(buckets.length), strong: true }]]);
  };
  var renderMoodLabelCloud = (ctx, data, W, H, config, theme, statsEl, hits) => {
    var _a;
    const entries = collectMoodEntries(data).filter((entry) => entry.valence !== void 0);
    if (!entries.length) return emptyState(ctx, W, H, theme, statsEl);
    const limit = Math.max(5, Math.floor(configNumber(config.limit, 28)));
    const buckets = aggregate(entries.flatMap((entry) => {
      var _a2;
      return (entry.labels.length ? entry.labels : [(_a2 = entry.label) != null ? _a2 : moodLabelForValence(entry.valence)]).map((key) => ({ key, valence: entry.valence }));
    }));
    buckets.sort((a, b) => b.count - a.count);
    const shown = buckets.slice(0, limit);
    const maxCount = Math.max(...shown.map((bucket) => bucket.count));
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    drawTitle(ctx, theme, "Mood label cloud", `${shown.length} labels \u2022 size = frequency, color = average valence`);
    let x = 22;
    let y = 76;
    let lineH = 0;
    for (const bucket of shown) {
      const avg3 = (_a = bucketAverage(bucket)) != null ? _a : 0;
      const size = 11 + Math.sqrt(bucket.count / maxCount) * 24;
      ctx.font = `700 ${size}px sans-serif`;
      const label = bucket.key;
      const w = ctx.measureText(label).width;
      if (x + w > W - 22) {
        x = 22;
        y += lineH + 12;
        lineH = 0;
      }
      if (y > H - 18) break;
      ctx.fillStyle = moodRgba(avg3, theme, 0.9);
      ctx.textAlign = "left";
      ctx.textBaseline = "alphabetic";
      ctx.fillText(label, x, y);
      hits.add({ shape: "rect", x, y: y - size, w, h: size + 4, title: label, details: [{ label: "Avg mood", value: `${moodLabelForValence(avg3)} (${formatMoodValence(avg3)})` }, { label: "Entries", value: String(bucket.count) }] });
      x += w + 16;
      lineH = Math.max(lineH, size);
    }
    renderInlineStats(statsEl, [[{ text: "Labels " }, { text: String(buckets.length), strong: true }], [{ text: "Entries " }, { text: String(entries.length), strong: true }]]);
  };
  var renderMoodVolatility = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    var _a, _b;
    const days = moodDaysWithValues(data);
    if (!days.length) return emptyState(ctx, W, H, theme, statsEl);
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const padL = 48, padR = 16, padT = 58, padB = 34;
    const plotW2 = W - padL - padR;
    const plotH = H - padT - padB;
    const slot = plotW2 / Math.max(days.length, 1);
    const volatilities = days.map((day) => day.minValence !== void 0 && day.maxValence !== void 0 ? day.maxValence - day.minValence : 0);
    const maxVol = Math.max(0.25, ...volatilities);
    const avgMood = (_a = average(days.map((day) => day.averageValence))) != null ? _a : 0;
    drawTitle(ctx, theme, "Mood volatility", "Bars = intraday range, line = daily average mood");
    drawValenceGrid(ctx, theme, padL, padT, plotW2, plotH);
    days.forEach((day, i) => {
      const x = padL + i * slot + slot / 2;
      const vol = volatilities[i];
      const barH = vol / maxVol * plotH * 0.45;
      ctx.fillStyle = hexToRgba(theme.colors.secondary, 0.35);
      ctx.beginPath();
      ctx.roundRect(x - Math.min(10, slot * 0.3), padT + plotH - barH, Math.max(2, Math.min(20, slot * 0.6)), barH, [3, 3, 0, 0]);
      ctx.fill();
    });
    ctx.strokeStyle = hexToRgba(theme.colors.accent, 0.75);
    ctx.lineWidth = 2;
    ctx.beginPath();
    days.forEach((day, i) => {
      const x = padL + i * slot + slot / 2;
      const y = yForValence(day.averageValence, padT, plotH);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
    days.forEach((day, i) => {
      const x = padL + i * slot + slot / 2;
      const y = yForValence(day.averageValence, padT, plotH);
      ctx.fillStyle = moodRgba(day.averageValence, theme, 0.85);
      ctx.beginPath();
      ctx.arc(x, y, 4.5, 0, Math.PI * 2);
      ctx.fill();
      if (days.length <= 14 || i % Math.ceil(days.length / 6) === 0 || i === days.length - 1) {
        ctx.fillStyle = theme.muted;
        ctx.font = "9px sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "top";
        ctx.fillText(shortDate(day.date), x, padT + plotH + 8);
      }
      hits.add({ shape: "rect", x: padL + i * slot, y: padT, w: slot, h: plotH + padB, title: formatDate(day.date), details: [{ label: "Avg mood", value: `${moodLabelForValence(day.averageValence)} (${formatMoodValence(day.averageValence)})` }, { label: "Volatility", value: formatMoodValence(volatilities[i]) }, { label: "Entries", value: String(day.entries.length) }], payload: day.day });
    });
    renderInlineStats(statsEl, [[{ text: "Avg mood " }, { text: `${moodLabelForValence(avgMood)} ${formatMoodValence(avgMood)}`, strong: true }], [{ text: "Avg volatility " }, { text: formatMoodValence((_b = average(volatilities)) != null ? _b : 0), strong: true }]]);
  };
  var renderMoodKindSplit = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    const days = collectMoodDays(data).map((day) => {
      const dailyValues = day.entries.filter((entry) => normalizeKind(entry.kind) === "daily").map((entry) => entry.valence).filter((value) => value !== void 0);
      const momentValues = day.entries.filter((entry) => normalizeKind(entry.kind) === "momentary").map((entry) => entry.valence).filter((value) => value !== void 0);
      return { ...day, daily: average(dailyValues), momentary: average(momentValues), dailyCount: dailyValues.length, momentaryCount: momentValues.length };
    }).filter((day) => day.daily !== void 0 || day.momentary !== void 0);
    if (!days.length) return emptyState(ctx, W, H, theme, statsEl);
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const padL = 50, padR = 18, padT = 64, padB = 34;
    const plotW2 = W - padL - padR;
    const plotH = H - padT - padB;
    const slot = plotW2 / Math.max(days.length, 1);
    drawTitle(ctx, theme, "Daily mood vs momentary emotions", `${days.length} days with State of Mind entries`);
    drawValenceGrid(ctx, theme, padL, padT, plotW2, plotH);
    const drawSeries = (key, color) => {
      ctx.strokeStyle = hexToRgba(color, 0.8);
      ctx.lineWidth = 2;
      ctx.beginPath();
      let active = false;
      days.forEach((day, i) => {
        const value = day[key];
        if (value === void 0) {
          active = false;
          return;
        }
        const x = padL + i * slot + slot / 2;
        const y = yForValence(value, padT, plotH);
        if (!active) {
          ctx.moveTo(x, y);
          active = true;
        } else ctx.lineTo(x, y);
      });
      ctx.stroke();
      days.forEach((day, i) => {
        const value = day[key];
        if (value === void 0) return;
        const x = padL + i * slot + slot / 2;
        const y = yForValence(value, padT, plotH);
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(x, y, key === "daily" ? 5 : 3.8, 0, Math.PI * 2);
        ctx.fill();
      });
    };
    drawSeries("daily", theme.colors.accent);
    drawSeries("momentary", theme.colors.secondary);
    ctx.font = "10px sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    [{ label: "Daily mood", color: theme.colors.accent }, { label: "Momentary", color: theme.colors.secondary }].forEach((item, i) => {
      const x = padL + i * 96;
      ctx.fillStyle = item.color;
      ctx.fillRect(x, padT - 18, 10, 6);
      ctx.fillStyle = theme.muted;
      ctx.fillText(item.label, x + 14, padT - 15);
    });
    days.forEach((day, i) => {
      if (days.length <= 14 || i % Math.ceil(days.length / 6) === 0 || i === days.length - 1) {
        ctx.fillStyle = theme.muted;
        ctx.font = "9px sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "top";
        ctx.fillText(shortDate(day.date), padL + i * slot + slot / 2, padT + plotH + 8);
      }
      hits.add({ shape: "rect", x: padL + i * slot, y: padT, w: slot, h: plotH + padB, title: formatDate(day.date), details: [{ label: "Daily", value: day.daily !== void 0 ? `${formatMoodValence(day.daily)} (${day.dailyCount})` : "\u2014" }, { label: "Momentary", value: day.momentary !== void 0 ? `${formatMoodValence(day.momentary)} (${day.momentaryCount})` : "\u2014" }], payload: day.day });
    });
    renderInlineStats(statsEl, [[{ text: "Daily avg " }, { text: formatMoodValence(average(days.map((day) => day.daily).filter((value) => value !== void 0))), strong: true }], [{ text: "Momentary avg " }, { text: formatMoodValence(average(days.map((day) => day.momentary).filter((value) => value !== void 0))), strong: true }]]);
  };
  var renderMoodCircadianClock = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    var _a, _b, _c, _d, _e, _f;
    const entries = collectMoodEntries(data).filter((entry) => entry.hour !== void 0 && entry.valence !== void 0);
    if (!entries.length) return emptyState(ctx, W, H, theme, statsEl);
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const cx = W / 2;
    const cy = H / 2 + 12;
    const r = Math.min(W, H - 42) * 0.36;
    const r0 = r * 0.46;
    drawTitle(ctx, theme, "Circadian mood clock", `${entries.length} entries by time of day`, 18, 24);
    ctx.strokeStyle = hexToRgba(theme.fg, 0.08);
    for (const rr of [r0, (r + r0) / 2, r]) {
      ctx.beginPath();
      ctx.arc(cx, cy, rr, 0, Math.PI * 2);
      ctx.stroke();
    }
    const byHour = /* @__PURE__ */ new Map();
    for (const entry of entries) {
      const hour = Math.floor((_a = entry.hour) != null ? _a : 0);
      byHour.set(hour, [...(_b = byHour.get(hour)) != null ? _b : [], entry.valence]);
    }
    for (let hour = 0; hour < 24; hour++) {
      const values = (_c = byHour.get(hour)) != null ? _c : [];
      const avg3 = average(values);
      const a0 = hour / 24 * Math.PI * 2 - Math.PI / 2;
      const a1 = (hour + 1) / 24 * Math.PI * 2 - Math.PI / 2;
      if (avg3 !== void 0) {
        ctx.fillStyle = moodRgba(avg3, theme, clamp(0.18 + values.length * 0.12, 0.25, 0.85));
        ctx.beginPath();
        ctx.arc(cx, cy, r, a0, a1);
        ctx.arc(cx, cy, r0, a1, a0, true);
        ctx.closePath();
        ctx.fill();
        hits.add({ shape: "sector", cx, cy, r0, r1: r, a0, a1, title: `${hour}:00`, details: [{ label: "Avg mood", value: `${moodLabelForValence(avg3)} (${formatMoodValence(avg3)})` }, { label: "Entries", value: String(values.length) }] });
      }
      if (hour % 6 === 0) {
        const a = a0;
        ctx.fillStyle = theme.muted;
        ctx.font = "10px sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(String(hour), cx + Math.cos(a) * (r + 16), cy + Math.sin(a) * (r + 16));
      }
    }
    for (const entry of entries) {
      const a = entry.hour / 24 * Math.PI * 2 - Math.PI / 2;
      const rr = lerp(r0 + 4, r - 5, (entry.valence + 1) / 2);
      const x = cx + Math.cos(a) * rr;
      const y = cy + Math.sin(a) * rr;
      ctx.fillStyle = moodRgba(entry.valence, theme, 0.95);
      ctx.beginPath();
      ctx.arc(x, y, 3, 0, Math.PI * 2);
      ctx.fill();
    }
    const avgAll = (_d = average(entries.map((entry) => entry.valence))) != null ? _d : 0;
    renderInlineStats(statsEl, [[{ text: "Avg mood " }, { text: `${moodLabelForValence(avgAll)} ${formatMoodValence(avgAll)}`, strong: true }], [{ text: "Most active hour " }, { text: `${(_f = (_e = Array.from(byHour.entries()).sort((a, b) => b[1].length - a[1].length)[0]) == null ? void 0 : _e[0]) != null ? _f : 0}:00`, strong: true }]]);
  };
  var renderMoodRecoveryTile = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    const days = moodDaysWithValues(data);
    if (!days.length) return emptyState(ctx, W, H, theme, statsEl);
    const latest = days[days.length - 1];
    const hrvValues = days.map((day) => day.hrv).filter((value) => value !== void 0);
    const hrvMin = hrvValues.length ? Math.min(...hrvValues) : void 0;
    const hrvMax = hrvValues.length ? Math.max(...hrvValues) : void 0;
    const moodScore = (latest.averageValence + 1) / 2 * 100;
    const sleepScore = latest.sleepSeconds ? clamp(latest.sleepSeconds / 3600 / 7.5 * 100, 0, 110) : 0;
    const hrvScore = latest.hrv !== void 0 && hrvMin !== void 0 && hrvMax !== void 0 && hrvMax !== hrvMin ? (latest.hrv - hrvMin) / (hrvMax - hrvMin) * 100 : latest.hrv !== void 0 ? 60 : 0;
    const exerciseScore = clamp(latest.exerciseMinutes / 30 * 100, 0, 100);
    const score = clamp(moodScore * 0.4 + sleepScore * 0.3 + hrvScore * 0.2 + exerciseScore * 0.1, 0, 100);
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    ctx.fillStyle = hexToRgba(moodHex(latest.averageValence, theme), theme.isDark ? 0.12 : 0.08);
    ctx.beginPath();
    ctx.roundRect(14, 14, W - 28, H - 28, 18);
    ctx.fill();
    ctx.strokeStyle = hexToRgba(theme.fg, 0.1);
    ctx.stroke();
    ctx.fillStyle = theme.muted;
    ctx.font = "11px sans-serif";
    ctx.textAlign = "left";
    ctx.fillText(formatDate(latest.date), 30, 40);
    ctx.fillStyle = theme.fg;
    ctx.font = "700 40px sans-serif";
    ctx.fillText(`${Math.round(score)}`, 30, 86);
    ctx.font = "600 18px sans-serif";
    ctx.fillStyle = moodHex(latest.averageValence, theme);
    ctx.fillText(moodLabelForValence(latest.averageValence), 104, 78);
    ctx.fillStyle = theme.muted;
    ctx.font = "11px sans-serif";
    ctx.fillText("recovery + mindset score", 104, 94);
    const bars = [
      { label: "Mood", value: moodScore, detail: formatMoodValence(latest.averageValence), color: moodHex(latest.averageValence, theme) },
      { label: "Sleep", value: sleepScore, detail: latest.sleepSeconds ? formatDuration(latest.sleepSeconds) : "\u2014", color: theme.colors.sleep.core },
      { label: "HRV", value: hrvScore, detail: latest.hrv !== void 0 ? `${Math.round(latest.hrv)} ms` : "\u2014", color: theme.colors.accent },
      { label: "Exercise", value: exerciseScore, detail: `${Math.round(latest.exerciseMinutes)} min`, color: theme.colors.secondary }
    ];
    const startY = 124;
    bars.forEach((bar, i) => {
      const y = startY + i * 32;
      ctx.fillStyle = theme.fg;
      ctx.font = "11px sans-serif";
      ctx.textAlign = "left";
      ctx.fillText(bar.label, 30, y);
      ctx.fillStyle = theme.muted;
      ctx.textAlign = "right";
      ctx.fillText(bar.detail, W - 30, y);
      ctx.fillStyle = hexToRgba(theme.fg, 0.08);
      ctx.beginPath();
      ctx.roundRect(30, y + 8, W - 60, 8, 4);
      ctx.fill();
      ctx.fillStyle = hexToRgba(bar.color, 0.85);
      ctx.beginPath();
      ctx.roundRect(30, y + 8, (W - 60) * clamp(bar.value / 100, 0, 1), 8, 4);
      ctx.fill();
    });
    hits.add({ shape: "rect", x: 14, y: 14, w: W - 28, h: H - 28, title: formatDate(latest.date), details: [{ label: "Score", value: String(Math.round(score)) }, { label: "Mood", value: `${moodLabelForValence(latest.averageValence)} (${formatMoodValence(latest.averageValence)})` }, { label: "Entries", value: String(latest.entries.length) }], payload: latest.day });
    renderStatBoxes(statsEl, [
      { value: String(Math.round(score)), label: "score", color: moodHex(latest.averageValence, theme) },
      { value: valencePercent(latest.averageValence), label: "mood" },
      { value: latest.sleepSeconds ? formatDuration(latest.sleepSeconds) : "\u2014", label: "sleep" },
      { value: latest.hrv !== void 0 ? `${Math.round(latest.hrv)}ms` : "\u2014", label: "HRV" }
    ]);
  };
  var renderMoodAssociationMatrix = (ctx, data, W, H, config, theme, statsEl, hits) => {
    var _a, _b;
    const entries = collectMoodEntries(data).filter((entry) => entry.valence !== void 0);
    if (!entries.length) return emptyState(ctx, W, H, theme, statsEl);
    const metric = configString(config.metric, "valence");
    const rowLimit = Math.max(3, Math.floor(configNumber(config.labels, 6)));
    const colLimit = Math.max(3, Math.floor(configNumber(config.associations, 6)));
    const labelBuckets = aggregate(entries.flatMap((entry) => {
      var _a2;
      return (entry.labels.length ? entry.labels : [(_a2 = entry.label) != null ? _a2 : moodLabelForValence(entry.valence)]).map((key) => ({ key, valence: entry.valence }));
    })).sort((a, b) => b.count - a.count).slice(0, rowLimit);
    const associationBuckets = aggregate(entries.flatMap((entry) => (entry.associations.length ? entry.associations : ["Unspecified"]).map((key) => ({ key, valence: entry.valence })))).sort((a, b) => b.count - a.count).slice(0, colLimit);
    if (!labelBuckets.length || !associationBuckets.length) return emptyState(ctx, W, H, theme, statsEl, "No mood labels/associations in range");
    const labels = labelBuckets.map((bucket) => bucket.key);
    const associations = associationBuckets.map((bucket) => bucket.key);
    const cells = /* @__PURE__ */ new Map();
    for (const entry of entries) {
      const ls = (entry.labels.length ? entry.labels : [(_a = entry.label) != null ? _a : moodLabelForValence(entry.valence)]).filter((label) => labels.includes(label));
      const as = (entry.associations.length ? entry.associations : ["Unspecified"]).filter((association) => associations.includes(association));
      for (const label of ls) for (const association of as) {
        const key = `${label}\0${association}`;
        const cell = (_b = cells.get(key)) != null ? _b : { count: 0, values: [] };
        cell.count += 1;
        cell.values.push(entry.valence);
        cells.set(key, cell);
      }
    }
    const maxCount = Math.max(1, ...Array.from(cells.values()).map((cell) => cell.count));
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const padL = 112, padR = 18, padT = 82, padB = 24;
    const cellW = (W - padL - padR) / associations.length;
    const cellH = (H - padT - padB) / labels.length;
    drawTitle(ctx, theme, "Mood association matrix", metric === "count" ? "Cells show entry count" : "Cells show average valence; opacity = count");
    ctx.fillStyle = theme.muted;
    ctx.font = "9px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "bottom";
    associations.forEach((association, col) => {
      ctx.save();
      ctx.translate(padL + col * cellW + cellW / 2, padT - 8);
      ctx.rotate(-Math.PI / 5);
      ctx.fillText(association.slice(0, 18), 0, 0);
      ctx.restore();
    });
    labels.forEach((label, row) => {
      const y = padT + row * cellH;
      ctx.fillStyle = theme.fg;
      ctx.font = "10px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      ctx.fillText(label.slice(0, 20), padL - 8, y + cellH / 2);
      associations.forEach((association, col) => {
        var _a2;
        const x = padL + col * cellW;
        const cell = cells.get(`${label}\0${association}`);
        const avg3 = cell ? (_a2 = average(cell.values)) != null ? _a2 : 0 : void 0;
        ctx.fillStyle = cell ? metric === "count" ? hexToRgba(theme.colors.secondary, clamp(cell.count / maxCount, 0.18, 0.88)) : moodRgba(avg3, theme, clamp(0.16 + cell.count / maxCount * 0.7, 0.18, 0.86)) : hexToRgba(theme.fg, 0.04);
        ctx.beginPath();
        ctx.roundRect(x + 2, y + 2, Math.max(2, cellW - 4), Math.max(2, cellH - 4), 4);
        ctx.fill();
        if (cell && cellW > 34 && cellH > 18) {
          ctx.fillStyle = theme.isDark ? "#fff" : "#111";
          ctx.globalAlpha = 0.78;
          ctx.font = "9px sans-serif";
          ctx.textAlign = "center";
          ctx.textBaseline = "middle";
          ctx.fillText(metric === "count" ? String(cell.count) : formatMoodValence(avg3), x + cellW / 2, y + cellH / 2);
          ctx.globalAlpha = 1;
        }
        if (cell) hits.add({ shape: "rect", x, y, w: cellW, h: cellH, title: `${label} \xD7 ${association}`, details: [{ label: "Entries", value: String(cell.count) }, { label: "Avg mood", value: `${moodLabelForValence(avg3)} (${formatMoodValence(avg3)})` }] });
      });
    });
    renderInlineStats(statsEl, [[{ text: "Labels " }, { text: String(labels.length), strong: true }], [{ text: "Associations " }, { text: String(associations.length), strong: true }], [{ text: "Cells " }, { text: String(cells.size), strong: true }]]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/medication-utils.ts
  function isRecord2(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function parseNumberValue(value) {
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value !== "string") return void 0;
    const normalized = value.trim().replace(/,/g, "");
    const match = /^[-+]?\d*\.?\d+(?:e[-+]?\d+)?/i.exec(normalized);
    if (!match) return void 0;
    const num = Number(match[0]);
    return Number.isFinite(num) ? num : void 0;
  }
  function stringValue(value) {
    if (typeof value === "string") {
      const trimmed = value.trim();
      return trimmed ? trimmed : void 0;
    }
    if (typeof value === "number" || typeof value === "boolean" || typeof value === "bigint") {
      return String(value);
    }
    return void 0;
  }
  function booleanValue(value) {
    if (typeof value === "boolean") return value;
    if (typeof value === "number" && Number.isFinite(value)) return value !== 0;
    if (typeof value !== "string") return void 0;
    const normalized = value.trim().toLowerCase();
    if (["true", "yes", "y", "1"].includes(normalized)) return true;
    if (["false", "no", "n", "0"].includes(normalized)) return false;
    return void 0;
  }
  function firstRaw(source, ...keys) {
    for (const key of keys) {
      if (Object.prototype.hasOwnProperty.call(source, key)) return source[key];
    }
    return void 0;
  }
  function firstString2(source, ...keys) {
    for (const key of keys) {
      const value = stringValue(source[key]);
      if (value !== void 0) return value;
    }
    return void 0;
  }
  function firstNumber2(source, ...keys) {
    for (const key of keys) {
      const value = parseNumberValue(source[key]);
      if (value !== void 0) return value;
    }
    return void 0;
  }
  function firstBoolean(source, ...keys) {
    for (const key of keys) {
      const value = booleanValue(source[key]);
      if (value !== void 0) return value;
    }
    return void 0;
  }
  function splitInlineArray(inner) {
    const parts = [];
    let current = "";
    let quote = null;
    let bracketDepth = 0;
    let braceDepth = 0;
    for (let i = 0; i < inner.length; i++) {
      const ch = inner[i];
      if ((ch === '"' || ch === "'") && inner[i - 1] !== "\\") {
        quote = quote === ch ? null : quote != null ? quote : ch;
      }
      if (!quote) {
        if (ch === "[") bracketDepth++;
        else if (ch === "]") bracketDepth = Math.max(0, bracketDepth - 1);
        else if (ch === "{") braceDepth++;
        else if (ch === "}") braceDepth = Math.max(0, braceDepth - 1);
        else if (ch === "," && bracketDepth === 0 && braceDepth === 0) {
          parts.push(current.trim());
          current = "";
          continue;
        }
      }
      current += ch;
    }
    if (current.trim()) parts.push(current.trim());
    return parts;
  }
  function splitYamlKeyValue(text) {
    const colonIdx = text.indexOf(":");
    if (colonIdx === -1) return null;
    const key = text.slice(0, colonIdx).trim();
    if (!key) return null;
    return [key, text.slice(colonIdx + 1).trim()];
  }
  function parseScalar(raw) {
    let value = raw.trim();
    if (!value) return null;
    if (value.startsWith('"') && value.endsWith('"') || value.startsWith("'") && value.endsWith("'")) {
      value = value.slice(1, -1);
      return value.replace(/\\"/g, '"').replace(/\\\\/g, "\\");
    }
    if (value.startsWith("[") && value.endsWith("]")) {
      return splitInlineArray(value.slice(1, -1)).map(parseScalar);
    }
    if (value.startsWith("{") && value.endsWith("}")) {
      try {
        return JSON.parse(value);
      } catch (e) {
        return value;
      }
    }
    const lower = value.toLowerCase();
    if (lower === "true") return true;
    if (lower === "false") return false;
    if (lower === "null" || lower === "~") return null;
    const num = Number(value.replace(/,/g, ""));
    if (Number.isFinite(num) && /^[-+]?\d/.test(value)) return num;
    return value;
  }
  function parseYamlishList(value) {
    const lines = value.split(/\r?\n/).map((line) => {
      var _a, _b;
      return { indent: (_b = (_a = /^ */.exec(line)) == null ? void 0 : _a[0].length) != null ? _b : 0, text: line.trim() };
    }).filter((line) => line.text && !line.text.startsWith("#"));
    if (!lines.length) return void 0;
    if (!lines.some((line) => line.text.startsWith("- "))) {
      const object = {};
      let hasKeys = false;
      for (const line of lines) {
        const pair = splitYamlKeyValue(line.text);
        if (!pair) return void 0;
        object[pair[0]] = parseScalar(pair[1]);
        hasKeys = true;
      }
      return hasKeys ? [object] : void 0;
    }
    const result = [];
    let current = null;
    let currentScalar;
    let hasCurrentScalar = false;
    for (const line of lines) {
      if (line.text.startsWith("- ")) {
        if (current) result.push(current);
        else if (hasCurrentScalar) result.push(currentScalar);
        current = null;
        currentScalar = void 0;
        hasCurrentScalar = false;
        const rest = line.text.slice(2).trim();
        if (!rest) {
          current = {};
          continue;
        }
        const pair = splitYamlKeyValue(rest);
        if (pair) {
          current = { [pair[0]]: parseScalar(pair[1]) };
          continue;
        }
        currentScalar = parseScalar(rest);
        hasCurrentScalar = true;
        continue;
      }
      if (current && line.indent > 0) {
        const pair = splitYamlKeyValue(line.text);
        if (pair) current[pair[0]] = parseScalar(pair[1]);
      }
    }
    if (current) result.push(current);
    else if (hasCurrentScalar) result.push(currentScalar);
    return result.length ? result : void 0;
  }
  function parseUnknownCollection(value) {
    if (Array.isArray(value)) return value;
    if (value == null) return [];
    if (isRecord2(value)) return [value];
    if (typeof value !== "string") return [];
    const trimmed = value.trim();
    if (!trimmed) return [];
    if (trimmed.startsWith("[") || trimmed.startsWith("{")) {
      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) return parsed;
        if (isRecord2(parsed)) return [parsed];
      } catch (e) {
      }
    }
    if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
      return splitInlineArray(trimmed.slice(1, -1)).map(parseScalar);
    }
    const yamlish = parseYamlishList(trimmed);
    if (yamlish) return yamlish;
    return trimmed.split(/[,;\n]/).map((item) => item.trim()).filter(Boolean);
  }
  function stringArrayFromUnknown2(value) {
    return parseUnknownCollection(value).flatMap((item) => {
      if (typeof item === "string" || typeof item === "number" || typeof item === "boolean") {
        const text = String(item).trim();
        return text ? [text] : [];
      }
      if (isRecord2(item)) {
        const name = firstString2(item, "display_name", "displayName", "name", "nickname");
        return name ? [name] : [];
      }
      return [];
    }).filter((item, index, all) => all.indexOf(item) === index);
  }
  function normalizeMedicationDetails(value) {
    return parseUnknownCollection(value).flatMap((item) => {
      if (typeof item === "string" || typeof item === "number" || typeof item === "boolean") {
        const name2 = String(item).trim();
        return name2 ? [{ name: name2, displayName: name2, display_name: name2 }] : [];
      }
      if (!isRecord2(item)) return [];
      const name = firstString2(item, "name", "medication", "display_name", "displayName", "nickname");
      const displayName = firstString2(item, "display_name", "displayName", "name", "nickname");
      const conceptIdentifier = firstString2(item, "concept_identifier", "conceptIdentifier", "medication_concept_identifier", "medicationConceptIdentifier");
      const generalForm = firstString2(item, "general_form", "generalForm", "form");
      const isArchived = firstBoolean(item, "is_archived", "isArchived", "archived");
      const hasSchedule = firstBoolean(item, "has_schedule", "hasSchedule", "scheduled");
      const nickname = firstString2(item, "nickname", "nick_name", "nickName");
      const rxnormCodes = stringArrayFromUnknown2(firstRaw(item, "rxnorm_codes", "rxnormCodes", "rxnorm"));
      const relatedCodings = parseUnknownCollection(firstRaw(item, "related_codings", "relatedCodings", "codings"));
      return [{
        ...item,
        name,
        conceptIdentifier,
        concept_identifier: conceptIdentifier,
        displayName,
        display_name: displayName,
        generalForm,
        general_form: generalForm,
        isArchived,
        is_archived: isArchived,
        hasSchedule,
        has_schedule: hasSchedule,
        nickname,
        relatedCodings: relatedCodings.length ? relatedCodings : void 0,
        related_codings: relatedCodings.length ? relatedCodings : void 0,
        rxnormCodes: rxnormCodes.length ? rxnormCodes : void 0,
        rxnorm_codes: rxnormCodes.length ? rxnormCodes : void 0
      }];
    });
  }
  function normalizeMedicationDoseEvents(value) {
    return parseUnknownCollection(value).flatMap((item) => {
      var _a;
      if (!isRecord2(item)) return [];
      const status = firstString2(item, "status", "dose_status", "doseStatus");
      const statusDisplay = (_a = firstString2(item, "status_display", "statusDisplay")) != null ? _a : statusLabel(status);
      const startDate = firstString2(item, "start_date", "startDate", "start", "started_at", "startedAt");
      const endDate = firstString2(item, "end_date", "endDate", "end", "ended_at", "endedAt");
      const scheduledDate = firstString2(item, "scheduled_date", "scheduledDate", "scheduled", "scheduled_at", "scheduledAt", "time", "timestamp");
      const doseQuantity = firstNumber2(item, "dose_quantity", "doseQuantity", "quantity");
      const scheduledDoseQuantity = firstNumber2(item, "scheduled_dose_quantity", "scheduledDoseQuantity", "scheduled_quantity", "scheduledQuantity");
      const scheduleType = firstString2(item, "schedule_type", "scheduleType", "schedule");
      const conceptIdentifier = firstString2(item, "medication_concept_identifier", "medicationConceptIdentifier", "concept_identifier", "conceptIdentifier");
      return [{
        ...item,
        name: firstString2(item, "name", "medication", "display_name", "displayName"),
        status,
        statusDisplay,
        status_display: statusDisplay,
        id: firstString2(item, "id", "identifier", "uuid"),
        medicationConceptIdentifier: conceptIdentifier,
        medication_concept_identifier: conceptIdentifier,
        startDate,
        start_date: startDate,
        endDate,
        end_date: endDate,
        scheduledDate,
        scheduled_date: scheduledDate,
        doseQuantity,
        dose_quantity: doseQuantity,
        scheduledDoseQuantity,
        scheduled_dose_quantity: scheduledDoseQuantity,
        unit: firstString2(item, "unit", "dose_unit", "doseUnit"),
        scheduleType,
        schedule_type: scheduleType,
        metadata: firstRaw(item, "metadata", "meta")
      }];
    }).sort((a, b) => medicationEventTimestamp(a).localeCompare(medicationEventTimestamp(b)));
  }
  function normalizeMedicationFields(source) {
    var _a, _b, _c, _d, _e, _f;
    const detailsRaw = firstRaw(source, "medication_details", "medicationDetails");
    const legacyMedicationsRaw = firstRaw(source, "medications", "medication_names", "medicationNames");
    const doseEventsRaw = firstRaw(source, "medication_dose_events", "medicationDoseEvents");
    let details = normalizeMedicationDetails(detailsRaw);
    const medicationNames = stringArrayFromUnknown2(legacyMedicationsRaw);
    if (!details.length && medicationNames.length) {
      details = medicationNames.map((name) => ({ name, displayName: name, display_name: name }));
    }
    const doseEvents = normalizeMedicationDoseEvents(doseEventsRaw);
    const derivedActive = details.filter((item) => item.isArchived !== true && item.is_archived !== true).length;
    const derivedArchived = details.filter((item) => item.isArchived === true || item.is_archived === true).length;
    const takenFromEvents = doseEvents.filter((event) => doseStatusKind(event.status) === "taken").length;
    const skippedFromEvents = doseEvents.filter((event) => doseStatusKind(event.status) === "skipped").length;
    const medicationCount = (_a = firstNumber2(source, "medication_count", "medicationCount")) != null ? _a : details.length || medicationNames.length || void 0;
    const activeMedicationCount = (_b = firstNumber2(source, "active_medication_count", "activeMedicationCount")) != null ? _b : details.length ? derivedActive : void 0;
    const archivedMedicationCount = (_c = firstNumber2(source, "archived_medication_count", "archivedMedicationCount")) != null ? _c : details.length ? derivedArchived : void 0;
    const medicationDoseCount = (_d = firstNumber2(source, "medication_dose_count", "medicationDoseCount")) != null ? _d : doseEvents.length || void 0;
    const medicationTakenCount = (_e = firstNumber2(source, "medication_taken_count", "medicationTakenCount")) != null ? _e : doseEvents.length ? takenFromEvents : void 0;
    const medicationSkippedCount = (_f = firstNumber2(source, "medication_skipped_count", "medicationSkippedCount")) != null ? _f : doseEvents.length ? skippedFromEvents : void 0;
    const patch = {};
    if (medicationCount !== void 0) {
      patch.medicationCount = medicationCount;
      patch.medication_count = medicationCount;
    }
    if (activeMedicationCount !== void 0) {
      patch.activeMedicationCount = activeMedicationCount;
      patch.active_medication_count = activeMedicationCount;
    }
    if (archivedMedicationCount !== void 0) {
      patch.archivedMedicationCount = archivedMedicationCount;
      patch.archived_medication_count = archivedMedicationCount;
    }
    if (medicationDoseCount !== void 0) {
      patch.medicationDoseCount = medicationDoseCount;
      patch.medication_dose_count = medicationDoseCount;
    }
    if (medicationTakenCount !== void 0) {
      patch.medicationTakenCount = medicationTakenCount;
      patch.medication_taken_count = medicationTakenCount;
    }
    if (medicationSkippedCount !== void 0) {
      patch.medicationSkippedCount = medicationSkippedCount;
      patch.medication_skipped_count = medicationSkippedCount;
    }
    if (medicationNames.length) patch.medications = medicationNames;
    if (details.length) {
      patch.medicationDetails = details;
      patch.medication_details = details;
    }
    if (doseEvents.length) {
      patch.medicationDoseEvents = doseEvents;
      patch.medication_dose_events = doseEvents;
    }
    return patch;
  }
  function medicationEventTimestamp(event) {
    var _a, _b, _c, _d, _e, _f;
    return (_f = (_e = (_d = (_c = (_b = (_a = event.scheduledDate) != null ? _a : event.scheduled_date) != null ? _b : event.startDate) != null ? _c : event.start_date) != null ? _d : event.endDate) != null ? _e : event.end_date) != null ? _f : "";
  }
  function doseStatusKind(status) {
    const normalized = (status != null ? status : "").trim().toLowerCase().replace(/[\s-]+/g, "_");
    if (["taken", "completed", "complete", "logged", "administered", "consumed", "done"].includes(normalized)) return "taken";
    if (["skipped", "missed", "not_taken", "not_taken_as_scheduled", "declined", "omitted"].includes(normalized)) return "skipped";
    return "other";
  }
  function statusLabel(status) {
    const kind = doseStatusKind(status);
    if (kind === "taken") return "Taken";
    if (kind === "skipped") return "Skipped";
    const raw = (status != null ? status : "Unknown").trim();
    if (!raw) return "Unknown";
    return raw.replace(/[_-]+/g, " ").replace(/\s+/g, " ").replace(/\b\w/g, (ch) => ch.toUpperCase());
  }
  function medicationDisplayName(item) {
    var _a, _b, _c, _d, _e, _f;
    return (_f = (_e = (_d = (_c = (_b = (_a = item.nickname) != null ? _a : item.displayName) != null ? _b : item.display_name) != null ? _c : item.name) != null ? _d : item.conceptIdentifier) != null ? _e : item.concept_identifier) != null ? _f : "Medication";
  }
  function doseEventMedicationName(event, details) {
    var _a, _b, _c;
    const direct = (_b = (_a = event.name) != null ? _a : event.displayName) != null ? _b : event.display_name;
    if (direct) return direct;
    const concept = (_c = event.medicationConceptIdentifier) != null ? _c : event.medication_concept_identifier;
    if (concept) {
      const match = details.find((item) => item.conceptIdentifier === concept || item.concept_identifier === concept);
      if (match) return medicationDisplayName(match);
    }
    return "Medication";
  }
  function medicationDoseQuantityLabel(event) {
    var _a, _b, _c;
    const quantity = (_c = (_b = (_a = event.doseQuantity) != null ? _a : event.dose_quantity) != null ? _b : event.scheduledDoseQuantity) != null ? _c : event.scheduled_dose_quantity;
    const unit = event.unit;
    if (quantity === void 0) return unit != null ? unit : "\u2014";
    const rounded = Number.isInteger(quantity) ? String(quantity) : String(Math.round(quantity * 100) / 100);
    return unit ? `${rounded} ${unit}` : rounded;
  }
  function getMedicationDaySummary(day) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _A, _B;
    const source = day;
    const hasExplicitMedicationField = [
      "medicationCount",
      "medication_count",
      "activeMedicationCount",
      "active_medication_count",
      "archivedMedicationCount",
      "archived_medication_count",
      "medicationDoseCount",
      "medication_dose_count",
      "medicationTakenCount",
      "medication_taken_count",
      "medicationSkippedCount",
      "medication_skipped_count",
      "medications",
      "medicationDetails",
      "medication_details",
      "medicationDoseEvents",
      "medication_dose_events"
    ].some((key) => Object.prototype.hasOwnProperty.call(source, key));
    const normalized = normalizeMedicationFields(source);
    const details = (_c = (_b = (_a = normalized.medicationDetails) != null ? _a : day.medicationDetails) != null ? _b : day.medication_details) != null ? _c : [];
    const doseEvents = (_f = (_e = (_d = normalized.medicationDoseEvents) != null ? _d : day.medicationDoseEvents) != null ? _e : day.medication_dose_events) != null ? _f : [];
    const medications = (_h = (_g = normalized.medications) != null ? _g : day.medications) != null ? _h : details.map(medicationDisplayName);
    const takenFromEvents = doseEvents.filter((event) => doseStatusKind(event.status) === "taken").length;
    const skippedFromEvents = doseEvents.filter((event) => doseStatusKind(event.status) === "skipped").length;
    const otherFromEvents = doseEvents.filter((event) => doseStatusKind(event.status) === "other").length;
    const medicationCount = (_m = (_l = (_k = (_j = (_i = normalized.medicationCount) != null ? _i : day.medicationCount) != null ? _j : day.medication_count) != null ? _k : details.length) != null ? _l : medications.length) != null ? _m : 0;
    const activeMedicationCount = (_p = (_o = (_n = normalized.activeMedicationCount) != null ? _n : day.activeMedicationCount) != null ? _o : day.active_medication_count) != null ? _p : details.filter((item) => item.isArchived !== true && item.is_archived !== true).length;
    const archivedMedicationCount = (_s = (_r = (_q = normalized.archivedMedicationCount) != null ? _q : day.archivedMedicationCount) != null ? _r : day.archived_medication_count) != null ? _s : details.filter((item) => item.isArchived === true || item.is_archived === true).length;
    const medicationDoseCount = (_v = (_u = (_t = normalized.medicationDoseCount) != null ? _t : day.medicationDoseCount) != null ? _u : day.medication_dose_count) != null ? _v : doseEvents.length;
    const medicationTakenCount = (_y = (_x = (_w = normalized.medicationTakenCount) != null ? _w : day.medicationTakenCount) != null ? _x : day.medication_taken_count) != null ? _y : takenFromEvents;
    const medicationSkippedCount = (_B = (_A = (_z = normalized.medicationSkippedCount) != null ? _z : day.medicationSkippedCount) != null ? _A : day.medication_skipped_count) != null ? _B : skippedFromEvents;
    const medicationOtherDoseCount = Math.max(0, medicationDoseCount - medicationTakenCount - medicationSkippedCount, otherFromEvents);
    const hasInventory = medicationCount > 0 || details.length > 0 || medications.length > 0 || hasExplicitMedicationField;
    const hasDoseCounts = medicationDoseCount > 0 || medicationTakenCount > 0 || medicationSkippedCount > 0 || hasExplicitMedicationField;
    const hasDoseEvents = doseEvents.length > 0;
    const hasMedicationData = hasExplicitMedicationField || hasInventory || hasDoseCounts || hasDoseEvents;
    return {
      date: day.date,
      medicationCount,
      activeMedicationCount,
      archivedMedicationCount,
      medicationDoseCount,
      medicationTakenCount,
      medicationSkippedCount,
      medicationOtherDoseCount,
      medications,
      details,
      doseEvents,
      hasInventory,
      hasDoseCounts,
      hasDoseEvents,
      hasMedicationData
    };
  }

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/medication-overview.ts
  function parsePositiveInt(value, defaultValue) {
    if (typeof value === "number" && Number.isFinite(value) && value > 0) return Math.floor(value);
    if (typeof value === "string") {
      const parsed = Number(value.trim());
      if (Number.isFinite(parsed) && parsed > 0) return Math.floor(parsed);
    }
    return defaultValue;
  }
  function pct(value, total) {
    return total > 0 ? `${Math.max(0, Math.min(100, value / total * 100)).toFixed(2)}%` : "0%";
  }
  function adherenceRate(taken, skipped) {
    const denominator = taken + skipped;
    return denominator > 0 ? taken / denominator : null;
  }
  function formatPercent(value) {
    return value == null ? "\u2014" : `${Math.round(value * 100)}%`;
  }
  function shortDate2(iso) {
    const d = /* @__PURE__ */ new Date(`${iso}T00:00:00`);
    if (Number.isNaN(d.getTime())) return iso;
    return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  }
  function formatDateTime(value) {
    if (!value) return "\u2014";
    const ms = Date.parse(value);
    if (!Number.isFinite(ms)) return value;
    return new Date(ms).toLocaleString("en-US", {
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit"
    });
  }
  function weekKey(dateIso) {
    const d = /* @__PURE__ */ new Date(`${dateIso}T00:00:00`);
    if (Number.isNaN(d.getTime())) return dateIso;
    const day = d.getDay();
    const mondayOffset = day === 0 ? -6 : 1 - day;
    const monday = new Date(d);
    monday.setDate(d.getDate() + mondayOffset);
    const y = monday.getFullYear();
    const m = String(monday.getMonth() + 1).padStart(2, "0");
    const dayOfMonth = String(monday.getDate()).padStart(2, "0");
    return `${y}-${m}-${dayOfMonth}`;
  }
  function monthKey(dateIso) {
    return dateIso.slice(0, 7);
  }
  function trendMode(dataDays, config) {
    var _a;
    const requested = String((_a = config.trend) != null ? _a : "auto").trim().toLowerCase();
    if (requested === "daily" || requested === "weekly" || requested === "monthly") return requested;
    if (dataDays > 120) return "monthly";
    if (dataDays > 31) return "weekly";
    return "daily";
  }
  function addStat(host, label, value, sublabel) {
    const card = host.createDiv({ cls: "health-md-med-stat" });
    card.createDiv({ cls: "health-md-med-stat-value", text: value });
    card.createDiv({ cls: "health-md-med-stat-label", text: label });
    if (sublabel) card.createDiv({ cls: "health-md-med-stat-sub", text: sublabel });
  }
  function statusClass(kind) {
    if (kind === "taken") return "is-taken";
    if (kind === "skipped") return "is-skipped";
    return "is-other";
  }
  function statusPrefix(kind) {
    if (kind === "taken") return "\u2713";
    if (kind === "skipped") return "\u21B7";
    return "?";
  }
  function addStatusBadge(host, rawStatus) {
    const kind = doseStatusKind(rawStatus);
    const badge = host.createSpan({ cls: `health-md-med-status ${statusClass(kind)}` });
    badge.createSpan({ cls: "health-md-med-status-symbol", text: statusPrefix(kind) });
    badge.appendChild(activeDocument.createTextNode(` ${statusLabel(rawStatus)}`));
  }
  function renderEmpty(host, message) {
    host.createDiv({ cls: "health-md-workout-empty", text: message });
  }
  function renderInventory(host, latest) {
    const section = host.createDiv({ cls: "health-md-med-section" });
    section.createEl("h4", { cls: "health-md-med-section-title", text: "Medication inventory" });
    const stats = section.createDiv({ cls: "health-md-med-stat-grid" });
    addStat(stats, "Total", String(latest.medicationCount));
    addStat(stats, "Active", String(latest.activeMedicationCount));
    addStat(stats, "Archived", String(latest.archivedMedicationCount));
    if (!latest.details.length) return;
    const list = section.createDiv({ cls: "health-md-med-inventory" });
    latest.details.forEach((item) => {
      var _a, _b, _c, _d;
      const row = list.createDiv({ cls: "health-md-med-inventory-row" });
      const name = row.createDiv({ cls: "health-md-med-inventory-name" });
      name.textContent = medicationDisplayName(item);
      const meta = row.createDiv({ cls: "health-md-med-inventory-meta" });
      const pieces = [
        (_a = item.generalForm) != null ? _a : item.general_form,
        ((_b = item.hasSchedule) != null ? _b : item.has_schedule) === true ? "Scheduled" : ((_c = item.hasSchedule) != null ? _c : item.has_schedule) === false ? "No schedule" : void 0,
        ((_d = item.isArchived) != null ? _d : item.is_archived) ? "Archived" : "Active"
      ].filter(Boolean);
      meta.textContent = pieces.join(" \u2022 ");
    });
  }
  function buildMedicationBreakdown(days, latestDetails) {
    const byName = /* @__PURE__ */ new Map();
    const ensure = (name, detail) => {
      const key = name.toLowerCase();
      let row = byName.get(key);
      if (!row) {
        row = { name, total: 0, taken: 0, skipped: 0, other: 0, detail };
        byName.set(key, row);
      } else if (!row.detail && detail) {
        row.detail = detail;
      }
      return row;
    };
    latestDetails.forEach((detail) => ensure(medicationDisplayName(detail), detail));
    for (const day of days) {
      const summary = getMedicationDaySummary(day);
      for (const event of summary.doseEvents) {
        const name = doseEventMedicationName(event, summary.details.length ? summary.details : latestDetails);
        const row = ensure(name);
        const kind = doseStatusKind(event.status);
        row[kind] += 1;
        row.total += 1;
      }
    }
    return Array.from(byName.values()).sort((a, b) => b.total - a.total || a.name.localeCompare(b.name));
  }
  function renderAdherence(host, taken, skipped, other) {
    const section = host.createDiv({ cls: "health-md-med-section" });
    section.createEl("h4", { cls: "health-md-med-section-title", text: "Adherence summary" });
    const total = taken + skipped + other;
    const stats = section.createDiv({ cls: "health-md-med-stat-grid" });
    addStat(stats, "Taken", String(taken));
    addStat(stats, "Skipped", String(skipped));
    if (other > 0) addStat(stats, "Other status", String(other));
    addStat(stats, "Adherence", formatPercent(adherenceRate(taken, skipped)), "taken \xF7 taken+skipped");
    if (total <= 0) {
      renderEmpty(section, "No medication dose counts were included for this date range.");
      return;
    }
    const bar = section.createDiv({ cls: "health-md-med-stack", attr: { "aria-label": `${taken} taken, ${skipped} skipped, ${other} other medication doses` } });
    bar.createDiv({ cls: "health-md-med-stack-segment is-taken", attr: { style: `width:${pct(taken, total)}` } });
    bar.createDiv({ cls: "health-md-med-stack-segment is-skipped", attr: { style: `width:${pct(skipped, total)}` } });
    bar.createDiv({ cls: "health-md-med-stack-segment is-other", attr: { style: `width:${pct(other, total)}` } });
    const legend = section.createDiv({ cls: "health-md-med-legend" });
    [
      { label: "Taken", value: taken, kind: "taken" },
      { label: "Skipped", value: skipped, kind: "skipped" },
      ...other > 0 ? [{ label: "Other", value: other, kind: "other" }] : []
    ].forEach((item) => {
      const el = legend.createSpan({ cls: `health-md-med-legend-item ${statusClass(item.kind)}` });
      el.createSpan({ cls: "health-md-med-legend-swatch" });
      el.appendChild(activeDocument.createTextNode(`${item.label}: ${item.value}`));
    });
  }
  function renderBreakdown(host, rows) {
    const section = host.createDiv({ cls: "health-md-med-section" });
    section.createEl("h4", { cls: "health-md-med-section-title", text: "Per-medication dose status" });
    if (!rows.length) {
      renderEmpty(section, "No medication inventory or dose events were included.");
      return;
    }
    const list = section.createDiv({ cls: "health-md-med-breakdown" });
    rows.forEach((row) => {
      const item = list.createDiv({ cls: "health-md-med-breakdown-row" });
      const header = item.createDiv({ cls: "health-md-med-breakdown-header" });
      header.createDiv({ cls: "health-md-med-breakdown-name", text: row.name });
      const rate = adherenceRate(row.taken, row.skipped);
      header.createDiv({ cls: "health-md-med-breakdown-rate", text: row.total > 0 ? `${formatPercent(rate)} adherence` : "No doses" });
      const total = Math.max(row.total, 1);
      const bar = item.createDiv({ cls: "health-md-med-stack is-small", attr: { "aria-label": `${row.name}: ${row.taken} taken, ${row.skipped} skipped, ${row.other} other` } });
      bar.createDiv({ cls: "health-md-med-stack-segment is-taken", attr: { style: `width:${pct(row.taken, total)}` } });
      bar.createDiv({ cls: "health-md-med-stack-segment is-skipped", attr: { style: `width:${pct(row.skipped, total)}` } });
      bar.createDiv({ cls: "health-md-med-stack-segment is-other", attr: { style: `width:${pct(row.other, total)}` } });
      const counts = item.createDiv({ cls: "health-md-med-breakdown-counts" });
      counts.textContent = `${row.taken} taken \u2022 ${row.skipped} skipped${row.other ? ` \u2022 ${row.other} other` : ""}`;
    });
  }
  function buildTrend(days, mode) {
    const byKey = /* @__PURE__ */ new Map();
    for (const day of days) {
      const summary = getMedicationDaySummary(day);
      if (!summary.hasMedicationData) continue;
      const key = mode === "monthly" ? monthKey(day.date) : mode === "weekly" ? weekKey(day.date) : day.date;
      const label = mode === "monthly" ? key : mode === "weekly" ? `Week of ${shortDate2(key)}` : shortDate2(day.date);
      let bucket = byKey.get(key);
      if (!bucket) {
        bucket = { key, label, total: 0, taken: 0, skipped: 0, other: 0 };
        byKey.set(key, bucket);
      }
      bucket.taken += summary.medicationTakenCount;
      bucket.skipped += summary.medicationSkippedCount;
      bucket.other += summary.medicationOtherDoseCount;
      bucket.total += summary.medicationDoseCount;
    }
    return Array.from(byKey.values()).sort((a, b) => a.key.localeCompare(b.key));
  }
  function renderTrend(host, days, config) {
    const mode = trendMode(days.length, config);
    const buckets = buildTrend(days, mode);
    const section = host.createDiv({ cls: "health-md-med-section" });
    section.createEl("h4", { cls: "health-md-med-section-title", text: `${mode.charAt(0).toUpperCase()}${mode.slice(1)} adherence trend` });
    const withDoses = buckets.filter((bucket) => bucket.total > 0 || bucket.taken > 0 || bucket.skipped > 0);
    if (withDoses.length < 2) {
      renderEmpty(section, "Add multiple days with medication dose counts to see a trend.");
      return;
    }
    const max = Math.max(...withDoses.map((bucket) => bucket.total), 1);
    const chart = section.createDiv({ cls: "health-md-med-trend" });
    withDoses.forEach((bucket) => {
      const col = chart.createDiv({ cls: "health-md-med-trend-col" });
      const bar = col.createDiv({ cls: "health-md-med-trend-bar", attr: { "aria-label": `${bucket.label}: ${bucket.taken} taken, ${bucket.skipped} skipped, ${bucket.other} other` } });
      bar.style.height = `${Math.max(8, bucket.total / max * 100)}%`;
      bar.createDiv({ cls: "health-md-med-trend-segment is-other", attr: { style: `height:${pct(bucket.other, bucket.total)}` } });
      bar.createDiv({ cls: "health-md-med-trend-segment is-skipped", attr: { style: `height:${pct(bucket.skipped, bucket.total)}` } });
      bar.createDiv({ cls: "health-md-med-trend-segment is-taken", attr: { style: `height:${pct(bucket.taken, bucket.total)}` } });
      col.createDiv({ cls: "health-md-med-trend-label", text: bucket.label });
    });
  }
  function renderRecentEvents(host, days, latestDetails, config) {
    var _a;
    const limit = parsePositiveInt((_a = config.limit) != null ? _a : config.recent, 12);
    const events = days.flatMap((day) => {
      const summary = getMedicationDaySummary(day);
      const details = summary.details.length ? summary.details : latestDetails;
      return summary.doseEvents.map((event) => ({ day, event, details }));
    }).sort((a, b) => medicationEventTimestamp(b.event).localeCompare(medicationEventTimestamp(a.event))).slice(0, limit);
    const section = host.createDiv({ cls: "health-md-med-section" });
    section.createEl("h4", { cls: "health-md-med-section-title", text: "Recent dose events" });
    if (!events.length) {
      renderEmpty(section, "No medication dose events were included for this date range.");
      return;
    }
    const wrapper = section.createDiv({ cls: "health-md-workout-table-wrap" });
    const table = wrapper.createEl("table", { cls: "health-md-workout-table health-md-med-event-table" });
    const thead = table.createEl("thead");
    const headerRow = thead.createEl("tr");
    ["Medication", "Status", "Time", "Dose", "Schedule"].forEach((heading) => headerRow.createEl("th", { text: heading }));
    const tbody = table.createEl("tbody");
    events.forEach(({ event, details }) => {
      var _a2, _b;
      const tr = tbody.createEl("tr");
      tr.createEl("td", { text: doseEventMedicationName(event, details) });
      const statusCell = tr.createEl("td");
      addStatusBadge(statusCell, event.status);
      tr.createEl("td", { text: formatDateTime(medicationEventTimestamp(event)) });
      tr.createEl("td", { text: medicationDoseQuantityLabel(event) });
      tr.createEl("td", { text: (_b = (_a2 = event.scheduleType) != null ? _a2 : event.schedule_type) != null ? _b : "\u2014" });
    });
  }
  var MEDICATION_EMPTY_MESSAGE = "No medication data in range. Health.md schema v2 exports medication_count, medication_details, and medication_dose_events.";
  function hasMedicationInventoryValues(summary) {
    return summary.medicationCount > 0 || summary.activeMedicationCount > 0 || summary.archivedMedicationCount > 0 || summary.details.length > 0 || summary.medications.length > 0;
  }
  function getMedicationRenderContext(data) {
    var _a, _b;
    const summaries = data.map(getMedicationDaySummary).filter((summary) => summary.hasMedicationData);
    if (!summaries.length) return null;
    const latestMedicationSummary = (_a = [...summaries].reverse().find((summary) => summary.hasInventory || summary.hasDoseEvents || summary.hasDoseCounts)) != null ? _a : summaries[summaries.length - 1];
    const latest = (_b = [...summaries].reverse().find(hasMedicationInventoryValues)) != null ? _b : latestMedicationSummary;
    const taken = summaries.reduce((sum, summary) => sum + summary.medicationTakenCount, 0);
    const skipped = summaries.reduce((sum, summary) => sum + summary.medicationSkippedCount, 0);
    const doseCount = summaries.reduce((sum, summary) => sum + summary.medicationDoseCount, 0);
    const other = Math.max(0, doseCount - taken - skipped);
    return { latest, taken, skipped, other };
  }
  function renderMedicationComponent(data, el, render) {
    el.addClass("health-md-med-container");
    const context = getMedicationRenderContext(data);
    if (!context) {
      renderEmpty(el, MEDICATION_EMPTY_MESSAGE);
      return;
    }
    render(context);
  }
  var renderMedicationInventory = (data, el) => {
    renderMedicationComponent(data, el, ({ latest }) => renderInventory(el, latest));
  };
  var renderMedicationAdherenceSummary = (data, el) => {
    renderMedicationComponent(
      data,
      el,
      ({ taken, skipped, other }) => renderAdherence(el, taken, skipped, other)
    );
  };
  var renderMedicationDoseStatus = (data, el) => {
    renderMedicationComponent(
      data,
      el,
      ({ latest }) => renderBreakdown(el, buildMedicationBreakdown(data, latest.details))
    );
  };
  var renderMedicationAdherenceTrend = (data, el, config) => {
    renderMedicationComponent(
      data,
      el,
      () => {
        var _a;
        return renderTrend(el, data, { ...config, trend: (_a = config.trend) != null ? _a : "daily" });
      }
    );
  };
  var renderMedicationRecentDoseEvents = (data, el, config) => {
    renderMedicationComponent(
      data,
      el,
      ({ latest }) => renderRecentEvents(el, data, latest.details, config)
    );
  };
  var renderMedicationOverview = (data, el, config, _theme) => {
    renderMedicationComponent(data, el, ({ latest, taken, skipped, other }) => {
      const header = el.createDiv({ cls: "health-md-med-header" });
      const title = header.createDiv({ cls: "health-md-med-title" });
      title.textContent = data.length > 1 ? "Medication overview" : `Medication overview \u2014 ${data[0].date}`;
      const subtitle = header.createDiv({ cls: "health-md-med-subtitle" });
      subtitle.textContent = data.length > 1 ? `${data[0].date} \u2013 ${data[data.length - 1].date}` : "Health.md schema v2 medication export";
      renderInventory(el, latest);
      renderAdherence(el, taken, skipped, other);
      renderBreakdown(el, buildMedicationBreakdown(data, latest.details));
      renderTrend(el, data, config);
      renderRecentEvents(el, data, latest.details, config);
    });
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/index.ts
  var VISUALIZATIONS = {
    "heart-terrain": renderHeartTerrain,
    "sleep-polar": renderSleepPolar,
    "step-spiral": renderStepSpiral,
    "oxygen-river": renderOxygenRiver,
    "breathing-wave": renderBreathingWave,
    "vitals-rings": renderVitalsRings,
    "walking-symmetry": renderWalkingSymmetry,
    "sleep-architecture": renderSleepArchitecture,
    "hrv-trend": renderHrvTrend,
    "activity-heatmap": renderActivityHeatmap,
    "sleep-quality-bars": renderSleepQualityBars,
    "workout-log": renderWorkoutLog,
    "activity-rings": renderActivityRings,
    "heart-range": renderHeartRange,
    "bar-chart": renderBarChart,
    "sleep-schedule": renderSleepSchedule,
    "weekday-average": renderWeekdayAverage,
    "oxygen-range": renderOxygenRange,
    "mood-trend": renderMoodTrend,
    "state-of-mind": renderMoodTrend,
    "mood-calendar-heatmap": renderMoodCalendarHeatmap,
    "mood-sleep-scatter": renderMoodSleepScatter,
    "mood-day-timeline": renderMoodDayTimeline,
    "mood-association-breakdown": renderMoodAssociationBreakdown,
    "mood-label-cloud": renderMoodLabelCloud,
    "mood-volatility": renderMoodVolatility,
    "mood-kind-split": renderMoodKindSplit,
    "mood-circadian-clock": renderMoodCircadianClock,
    "mood-recovery-tile": renderMoodRecoveryTile,
    "mood-association-matrix": renderMoodAssociationMatrix,
    "workout-heart-rate": renderWorkoutHeartRate,
    "workout-zones": renderWorkoutZones,
    "workout-heart-rate-zones": renderWorkoutZones,
    "workout-trends": renderWorkoutTrends
  };
  var HTML_VISUALIZATIONS = {
    "intro-stats": renderIntroStats,
    "summary-card": renderSummaryCard,
    "trend-tile": renderTrendTile,
    "workout-map": renderWorkoutMap,
    "workout-intervals": renderWorkoutIntervals,
    "workout-laps": renderWorkoutIntervals,
    "medication-overview": renderMedicationOverview,
    "medications": renderMedicationOverview,
    "medication-adherence": renderMedicationOverview,
    "medication-inventory": renderMedicationInventory,
    "medication-adherence-summary": renderMedicationAdherenceSummary,
    "medication-dose-status": renderMedicationDoseStatus,
    "per-medication-dose-status": renderMedicationDoseStatus,
    "medication-adherence-trend": renderMedicationAdherenceTrend,
    "medication-daily-adherence-trend": renderMedicationAdherenceTrend,
    "medication-recent-dose-events": renderMedicationRecentDoseEvents,
    "medication-dose-events": renderMedicationRecentDoseEvents
  };

  // ../../../../../private/var/folders/dj/3srkns7n7qxb2kp1vxb_4xjm0000gn/T/healthmd-viz-bundle-G8U103/healthmd-viz-entry.ts
  window.HealthMdPluginVisualizations = {
    source: "obsidian-health-md src/visualizations",
    sourceRepo: "/Users/codybontecou/projects/obsidian-plugin-hub/obsidian-health-md",
    generatedBy: "website/scripts/build-plugin-visualizations.mjs",
    colorSchemes: COLOR_SCHEMES,
    resolveTheme,
    renderers: VISUALIZATIONS,
    htmlRenderers: HTML_VISUALIZATIONS
  };
})();
