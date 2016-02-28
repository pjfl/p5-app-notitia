// Perl Artistic license except where stated otherwise

Date.extend( 'nowMET', function() { // Calculate Middle European Time UTC + 1
   var now = new Date();

   now.setTime( now.getTime() + (now.getTimezoneOffset() + 60) * 60 * 1000 );

   return now;
} );

Date.extend( 'nowUTC', function() { // Calculate UTC
   var now = new Date();

   now.setTime( now.getTime() + now.getTimezoneOffset() * 60 * 1000 );

   return now;
} );

Date.implement( {
   dayFraction: function() { // Elapsed time since SOD in thousandths of a day
      return ( this.getHours() * 3600 + this.getMinutes() * 60
               + this.getSeconds() ) / 86.4;
   },

   swatchTime: function() {
      var met_day_fraction = Date.nowMET().dayFraction();

      return Number.from( met_day_fraction ).format( { decimals: 2 } );
   }
} );

Options.implement( {
   aroundSetOptions: function( options ) {
      options         = options || {};
      this.collection = [];
      this.context    = {};
      this.debug      = false;
      this.log        = function() {};

      [ 'config', 'context', 'debug' ].each( function( attr ) {
         if (options[ attr ] != undefined) {
            this[ attr ] = options[ attr ]; delete options[ attr ];
         }
      }.bind( this ) );

      this.setOptions( options ); var opt = this.options;

      if (! this.config && this.context.config && opt.config_attr)
         this.config = this.context.config[ opt.config_attr ];

      if (! this.config) this.config = {};

      if (this.context.collect) this.context.collect( this );

      if (this.context.window && this.context.window.logger)
         this.log = this.context.window.logger

      return this;
   },

   build: function() {
      var selector = this.options.selector;

      if (selector) $$( selector ).each( function( el ) {
         if (! this.collection.contains( el )) {
            this.collection.include( el ); this.attach( el );
         }
      }, this );
   },

   mergeOptions: function( arg ) {
      arg = arg || 'default';

      if (typeOf( arg ) != 'object') { arg = this.config[ arg ] || {} }

      return Object.merge( Object.clone( this.options ), arg );
   }
} );

String.implement( {
   escapeHTML: function() {
      var text = this;
      text = text.replace( /\&/g, '&amp;'  );
      text = text.replace( /\>/g, '&gt;'   );
      text = text.replace( /\</g, '&lt;'   );
      text = text.replace( /\"/g, '&quot;' );
      return text;
   },

   pad: function( length, str, direction ) {
      if (this.length >= length) return this;

      var pad = (str == null ? ' ' : '' + str)
         .repeat( length - this.length )
         .substr( 0, length - this.length );

      if (!direction || direction == 'right') return this + pad;
      if (direction == 'left') return pad + this;

      return pad.substr( 0, (pad.length / 2).floor() )
           + this + pad.substr( 0, (pad.length / 2).ceil() );
   },

   repeat: function( times ) {
      return new Array( times + 1 ).join( this );
   },

   ucfirst: function() {
      return this.charAt( 0 ).toUpperCase() + this.slice( 1 );
   },

   unescapeHTML: function() {
      var text = this;
      text = text.replace( /\&amp\;/g,    '&' );
      text = text.replace( /\&dagger\;/g, '\u2020' );
      text = text.replace( /\&gt\;/g,     '>' );
      text = text.replace( /\&hellip\;/g, '\u2026' );
      text = text.replace( /\&lt\;/g,     '<' );
      text = text.replace( /\&nbsp\;/g,   '\u00a0' );
      text = text.replace( /\&\#160\;/g,  '\u00a0' );
      text = text.replace( /\&quot\;/g,   '"' );
      return text;
   }
} );

var Cookies = new Class( {
   Implements: [ Options ],

   options  : {
      domain: '',
      expire: 90,
      name  : 'state',
      path  : '/',
      prefix: '',
      secure: false
   },

   initialize: function( options ) {
      this.setOptions( options ); var opt = this.options;

      var cookie_name = (opt.prefix ? opt.prefix + '_' : '') + opt.name;
      var cookie_opts = { domain: opt.domain, duration: opt.expire,
                          path  : opt.path,   secure  : opt.secure };

      this.cookie = new Cookie( cookie_name, cookie_opts );
   },

   get: function( name ) {
      var cookie  = this.cookie.read(); if (! (name && cookie)) return cookie;

      var cookies = cookie.split( '+' );

      for (var i = 0, cl = cookies.length; i < cl; i++) {
         var pair = cookies[ i ].split( '~' );

         if (unescape( pair[ 0 ] ) == name)
            return pair[ 1 ] != 'null' ? unescape( pair[ 1 ] ) : null;
      }

      return '';
   },

   remove: function( name ) {
      var i, cookie = this.cookie.read();

      if (cookie && name) name = escape( name );
      else return false;

      if ((i = cookie.indexOf( name + '~' )) < 0) return false;

      var j = cookie.substring( i ).indexOf( '+' );

      if (i == 0) cookie = (j < 0) ? '' : cookie.substring( j + 1 );

      if (i > 0) {
         cookie = (j < 0)
                ? cookie.substring( 0, i - 1 )
                : cookie.substring( 0, i - 1 ) + cookie.substring( i + j );
      }

      return this.cookie.write( cookie );
   },

   set: function( name, value ) {
      var cookie = this.cookie.read(), i;

      if (name) name = escape( name );
      else return;

      if (value) value = escape( value );

      if (cookie) {
         if ((i = cookie.indexOf( name + '~' )) >= 0) {
            var j = cookie.substring( i ).indexOf( '+' );

            if (i == 0) {
               cookie = (j < 0) ? name + '~' + value
                                : name + '~' + value + cookie.substring( j );
            }
            else {
               cookie = (j < 0) ? cookie.substring( 0, i ) + name + '~' + value
                                : cookie.substring( 0, i ) + name + '~' + value
                                + cookie.substring( i + j );
            }
         }
         else { cookie += '+' + name + '~' + value }
      }
      else { cookie = name + '~' + value }

      return this.cookie.write( cookie );
   }
} );

var Debouncer = new Class( {
   initialize: function( cb ) {
      this.callback    = cb;
      this.rafCallback = this._update.bind( this );
      this.ticking     = false;

      window.requestAnimationFrame = window.requestAnimationFrame
                                  || window.webkitRequestAnimationFrame
                                  || window.mozRequestAnimationFrame;
   },

   handleEvent: function() {
      this._requestTick();
   },

   _requestTick: function() {
      if (!this.ticking) {
         this.ticking = true; requestAnimationFrame( this.rafCallback );
      }
   },

   _update: function() {
      this.callback && this.callback(); this.ticking = false;
   }
} );

var Dialog = new Class( {
   Implements: [ Options ],

   Binds: [ '_keyup' ],

   options: {
      klass   : 'dialog',
      maskOpts: {},
      title   : 'Options',
      useIcon : false,
      useMask : true,
   },

   initialize: function( el, body, options ) {
      this.setOptions( options ); this.attach( this.create( el, body ) );
   },

   attach: function( el ) {
      el.addEvent( 'click', function( ev ) {
         ev.stop(); this.hide() }.bind( this ) );
      window.addEvent( 'keyup', this._keyup );
   },

   create: function( el, body ) {
      var opt = this.options;

      if (opt.useMask) this.mask = new Mask( el, opt.maskOpts );

      this.parent = this.mask ? this.mask.element : $( 'body' );
      this.dialog = new Element( 'div', { 'class': opt.klass } ).hide()
          .inject( this.parent );

      var title   = new Element( 'div', { 'class': opt.klass + '-title' } )
          .appendText( opt.title ).inject( this.dialog );

      if (opt.useIcon) {
         this.close = new Element( 'i', {
            'class': opt.klass + '-close close-icon' } ).inject( title );
      }
      else {
         this.close = new Element( 'span', {
            'class': opt.klass + '-close' } ).appendText( 'x' ).inject( title );
      }

      body.addClass( opt.klass + '-body' ).inject( this.dialog );
      return this.close;
   },

   hide: function() {
      this.visible = false; this.dialog.hide(); if (this.mask) this.mask.hide();
   },

   position: function() {
      this.dialog.position( { relativeTo: this.parent } );
   },

   show: function() {
      if (this.mask) this.mask.show();

      this.position(); this.dialog.show(); this.visible = true;
   },

   _keyup: function( ev ) {
      ev = new DOMEvent( ev ); ev.stop();

      if (this.visible && (ev.key == 'esc')) this.hide();
   }
} );

var Headroom = new Class( {
   Implements: [ Options ],

   options       : {
      classes    : {
         notTop  : 'headroom-not-top',
         pinned  : 'headroom-pinned',
         top     : 'headroom-top',
         unpinned: 'headroom-unpinned'
      },
      offset     : 0,
      selector   : '.headroom',
      tolerance  : 0
   },

   initialize: function( options ) {
      this.aroundSetOptions( options ); this.props = {}; this.build();
   },

   attach: function( el ) {
      if (! el.id) el.id = String.uniqueID();

      var debouncer = new Debouncer( function () {
         this.update( el.id ) }.bind( this ) );

      this.props[ el.id ] = { debouncer: debouncer, prevScrollY: 0 };

      var attacher = function() {
         this.props[ el.id ].prevScrollY = window.getScroll().y;
         window.addEvent( 'scroll', debouncer.handleEvent.bind( debouncer ) );
      };

      attacher.delay( 100, this );
   },

   isOutOfBounds: function( scrollY ) {
      var pastTop = scrollY < 0;
      var pastBot = scrollY + window.getSize().y > document.getScrollSize().y;

      return pastTop || pastBot;
   },

   notTop: function( el ) {
      var opts = this.options, classes = opts.classes;

      if (!el.hasClass( classes.notTop )) {
         el.addClass( classes.notTop ); el.removeClass( classes.top );
         opts.onNotTop && opts.onNotTop.call( this );
      }
   },

   pin: function( el ) {
      var opts = this.options, classes = opts.classes;

      if (el.hasClass( classes.unpinned )) {
         el.removeClass( classes.unpinned ); el.addClass( classes.pinned );
         opts.onPin && opts.onPin.call( this );
      }
   },

   shouldPin: function( id, currentScrollY ) {
      var prevScrollY = this.props[ id ].prevScrollY;
      var outOfBand   = this.toleranceExceeded( prevScrollY, currentScrollY );
      var scrollingUp = currentScrollY <  prevScrollY;
      var pastOffset  = currentScrollY <= this.options.offset;

      return (scrollingUp && outOfBand) || pastOffset;
   },

   shouldUnpin: function( id, currentScrollY ) {
      var prevScrollY   = this.props[ id ].prevScrollY;
      var outOfBand     = this.toleranceExceeded( prevScrollY, currentScrollY );
      var scrollingDown = currentScrollY >  prevScrollY;
      var pastOffset    = currentScrollY >= this.options.offset;

      return scrollingDown && pastOffset && outOfBand;
   },

   toleranceExceeded: function( prevScrollY, currentScrollY ) {
      return Math.abs( currentScrollY - prevScrollY ) >= this.options.tolerance;
   },

   top: function( el ) {
      var opts = this.options, classes = opts.classes;

      if (!el.hasClass( classes.top )) {
         el.addClass( classes.top ); el.removeClass( classes.notTop );
         opts.onTop && opts.onTop.call( this );
      }
   },

   unpin: function( el ) {
      var opts = this.options, classes = opts.classes;

      if (el.hasClass( classes.pinned ) || !el.hasClass( classes.unpinned )) {
         el.addClass( classes.unpinned ); el.removeClass( classes.pinned );
         opts.onUnpin && opts.onUnpin.call( this );
      }
   },

   update: function( id ) {
      var el = $( id ), currentScrollY = window.getScroll().y;

      if (this.isOutOfBounds( currentScrollY )) return;

      if (currentScrollY <= this.options.offset ) this.top( el );
      else this.notTop( el );

      if (this.shouldUnpin( id, currentScrollY )) { this.unpin( el ); }
      else if (this.shouldPin( id, currentScrollY )) { this.pin( el ); }

      this.props[ id ].prevScrollY = currentScrollY;
   }
} );

var LinkFader = new Class( {
   Implements: [ Options ],

   options    : {
      fc      : 'ff0000', // Fade to colour
      inBy    : 6,        // Fade in colour inc/dec by
      outBy   : 6,        // Fade out colour inc/dec by
      selector: '.fade',  // Class name matching links to fade
      speed   : 20        // Millisecs between colour changes
   },

   initialize: function( options ) {
      this.aroundSetOptions( options ); this.build();
   },

   attach: function( el ) {
      el.addEvent( 'mouseover', this.startFade.bind( this, el ) );
      el.addEvent( 'mouseout',  this.clearFade.bind( this, el ) );
   },

   clearFade: function( el ) {
      if (el.timer) clearInterval( el.timer );

      el.timer = this.fade.periodical( this.options.speed, this, [ el, 0 ] );
   },

   currentColour: function( el ) {
      var cc = el.getStyle( 'color' ), temp = '';

      if (cc.length == 4 && cc.substring( 0, 1 ) == '#') {
         for (var i = 0; i < 3; i++) {
            temp += cc.substring( i + 1, i + 2 ) + cc.substring( i + 1, i + 2);
         }

         cc = temp;
      }
      else if (cc.indexOf('rgb') != -1) { cc = cc.rgbToHex().substring(1, 7) }
      else if (cc.length == 7)          { cc = cc.substring( 1, 7 ) }
      else                              { cc = this.options.fc }

      return cc;
   },

   fade: function( el, d ) {
      var cc = this.currentColour( el ).hexToRgb( true );
      var tc = (d == 1)  ? this.options.fc.hexToRgb( true )
             : el.colour ? el.colour.hexToRgb( true )
                         : [ 0, 0, 0 ];

      if (tc[ 0 ] == cc[ 0 ] && tc[ 1 ] == cc[ 1 ] && tc[ 2 ] == cc[ 2 ]) {
         clearInterval( el.timer ); el.timer = null; return;
      }

      el.setStyle( 'color', this.nextColour( tc, cc, d ) );
   },

   nextColour: function( tc, cc, d ) {
      var change = (d == 1) ? this.options.inBy : this.options.outBy;
      var colour;

      for (var i = 0; i < 3; i++) {
         var diff, nc = cc[ i ];

         if (! colour) colour = 'rgb(';
         else colour += ',';

         if (tc[ i ]-cc[ i ] > 0) { diff   = tc[ i ] - cc[ i ] }
         else                     { diff   = cc[ i ] - tc[ i ] }
         if (diff    < change)    { change = diff }
         if (cc[ i ] > tc[ i ])   { nc     = cc[ i ] - change }
         if (cc[ i ] < tc[ i ])   { nc     = cc[ i ] + change }
         if (nc      < 0)         { nc     = 0 }
         if (nc      > 255)       { nc     = 255 }

         colour += nc;
      }

      colour += ')';
      return colour;
   },

   startFade: function( el ) {
      if (el.timer) {
         clearInterval( el.timer ); el.timer = null;

         if (el.colour) el.setStyle( 'color', el.colour.hexToRgb() );
      }

      el.colour = this.currentColour( el );
      el.timer  = this.fade.periodical( this.options.speed, this, [ el, 1 ] );
   }
} );

var LoadMore = new Class( {
   attach: function( el ) {
      var cfg; if (! (cfg = this.config[ el.id ])) return;

      var event = cfg.event || 'click';

      if (event == 'load') {
         this[ cfg.method ].apply( this, cfg.args ); return;
      }

      el.addEvent( event, function( ev ) {
         ev.stop(); this[ cfg.method ].apply( this, cfg.args ) }.bind( this ) );
   },

   request: function( url, id, val, on_complete ) {
      if (on_complete) this.onComplete = on_complete;

      if (url.substring( 0, 4 ) != 'http') url = this.options.url + url;

      new Request.JSON( { onSuccess: this._response.bind( this ), url: url } )
                  .get( { 'id': id, 'val': val } );
   },

   _response: function( resp ) {
      $( resp.id ).set( 'html', resp.html.unescapeHTML() );

      if (resp.script) Browser.exec( resp.script );

      if (this.onComplete) this.onComplete.call( this.context, resp );
   }
} );

/* Formally jquery-notification 1.1
 * Dual licensed under the MIT or GPL Version 2 licenses.
 * http://www.opensource.org/licenses/mit-license.php
 * http://www.gnu.org/licenses/gpl-2.0.html */
var NoticeBoard = new Class( {
   Implements: [ Options ],

   options      : {
      canClose  : true,
      click     : function() {},
      content   : '',
      fadeIn    : 400,
      fadeOut   : 600,
      hideDelay : 7000,
      horizontal: 'right',
      limit     : 3,
      noshow    : false,
      queue     : true,
      slideUp   : 600,
      vertical  : 'bottom'
   },

   initialize: function( options ) {
      this.aroundSetOptions( options ); var opt = this.options;

      var klass = 'notice-board nb-' + opt.vertical + ' nb-' + opt.horizontal;

      this.board = $$( '.' + klass )[ 0 ];

      // Create notification container
      if (! this.board) this.board =
         new Element( 'div', { class: klass } ).inject( $( 'body' ) );

      this.queue = [];
   },

   create: function( content, options ) { // Create new notification and show
      var opt  = this.mergeOptions( options );
      var qlen = this.board.getChildren( '.notice:not(.hiding)' ).length;

      if (opt.limit && qlen >= opt.limit) { // Limit reached
         if (opt.queue) this.queue.push( [ content, opt ] );
         return;
      }

      var el = new Element( 'div', { class: 'notice' } ).set( 'html', content );

      if (opt.canClose) {
         new Element( 'div', { class: 'close-icon' } ).inject( el, 'top' );
      }

      el.store( 'notice:options', opt ); this.attach( el );

      if (!opt.noshow) this.show( el );

      return el;
   },

   attach: function( el ) {
      var opt = el.retrieve( 'notice:options' ) || this.options;

      el.addEvents( {
         click: function( ev ) {
            ev.stop(); opt.click.call( this, el ) }.bind( this ),

         mouseenter: function( ev ) { // Avoid hide when hover
            ev.stop(); el.addClass( 'hover' );

            if (el.hasClass( 'hiding' )) {
               el.get( 'slide' ).pause(); // Recover
               el.get( 'tween' ).pause();
               el.set( 'tween', { duration: opt.fadeIn, property: 'opacity' } );
               el.tween( 1 );
               el.get( 'slide' ).show();
               el.removeClass( 'hiding' );
               el.addClass( 'pending' );
            }
         },

         mouseleave: function( ev ) { // Hide was pending
            if (el.hasClass( 'pending' )) this.hide( el );
            el.removeClass( 'hover' );
         }.bind( this )
      } );

      var icon; if (icon = el.getChildren( '.close-icon' )[ 0 ]) {
         icon.addEvent( 'click', function( ev ) { // Close button
            ev.stop(); this.hide( el ) }.bind( this ) );
      }
   },

   show: function( el ) { // Append to board and show
      var opt    = el.retrieve( 'notice:options' ) || this.options;
      var fadein = opt.fadeIn;

      el.inject( this.board, opt.vertical == 'top' ? 'bottom' : 'top' );
      el.set( 'tween', { duration: fadein, property: 'opacity' } ).tween( 1 );

      if (!opt.hideDelay) return;

      el.noticeTimer = function() { // Hide timer
         el.hasClass( 'hover' ) ? el.addClass( 'pending' ) : this.hide( el );
      }.delay( opt.hideDelay, this );
   },

   hide: function( el ) {
      var opt = el.retrieve( 'notice:options' ) || this.options;

      el.addClass( 'hiding' );

      el.set( 'tween', { duration: opt.fadeOut, onComplete: function() {
         var q; if (q = this.queue.shift()) this.create( q[ 0 ], q[ 1 ] );
      }.bind( this ), property: 'opacity' } ).tween( 0 );

      el.set( 'slide', { duration: opt.slideUp, onComplete: function() {
         el.getParent().destroy() } } ).slide( 'out' );
   }
} );

var Replacements = new Class( {
   Implements: [ Options ],

   options              : {
      textarea_container: 'expanding_area',
      textarea_preformat: 'expanding_spacer',
      config_attr       : 'inputs',
      event             : 'click',
      method            : 'toggle',
      selector          : [ '.autosize', 'input[type=checkbox]',
                            'input[type=password].reveal',
                            'input[type=radio]' ],
      suffix            : '_replacement'
   },

   initialize: function( options ) {
      this.aroundSetOptions( options ); this.build();
   },

   build: function() {
      this.options.selector.each( function( selector ) {
         $$( selector ).each( function( el ) {
            if (! el.id) el.id = String.uniqueID();

            if (! this.collection.contains( el.id )) {
               this.collection.include( el.id ); this.createMarkup( el );
            }

            this.attach( el );
         }, this );
      }, this );
   },

   createMarkup: function( el ) {
      var opt = this.mergeOptions( el.id ), new_id = el.id + opt.suffix;

      if (el.type == 'checkbox' || el.type == 'radio') {
         el.setStyles( { margin: 0, padding: 0,
                         position: 'absolute', left: '-9999px' } );
         new Element( 'span', {
            'class': 'checkbox' + (el.checked ? ' checked' : ''),
            id     : new_id,
            name   : el.name
         } ).inject( el, 'before' );
         return;
      }

      if (el.type == 'textarea' || el.type == 'text') {
         var div  = new Element( 'div',  { 'class': opt.textarea_container } );
         var pre  = new Element( 'pre',  { 'class': opt.textarea_preformat } );
         var span = new Element( 'span', { id: new_id } );

         div.inject( el, 'before' ); pre.inject( div ); div.grab( el );
         span.inject( pre ); new Element( 'br' ).inject( pre );
         span.set( 'text', el.value );
      }

      return;
   },

   attach: function( el ) {
      var opt = this.mergeOptions( el.id );

      if (el.type == 'textarea' || el.type == 'text') {
         this._add_events( el, el, 'keyup', 'set_text' );
      }
      else {
         var replacement = $( el.id + opt.suffix ) || el;

         this._add_events( el, replacement, opt.event, opt.method );
      }
   },

   _add_events: function( el, replacement, events, methods ) {
      methods = Array.from( methods );

      Array.from( events ).each( function( event, index ) {
         var handler, key = 'event:' + event;

         if (! (handler = replacement.retrieve( key ))) {
            handler = function( ev ) {
               ev.stop(); this[ methods[ index ] ].call( this, el );
            }.bind( this );
            replacement.store( key, handler );
         }

         replacement.addEvent( event, handler );
      }, this );
   },

   hide_password: function( el ) {
      el.setProperty( 'type', 'password' );
   },

   set_text: function( el ) {
      var opt = this.mergeOptions( el.id );

      $( el.id + opt.suffix ).set( 'text', el.value );
   },

   show_password: function( el ) {
      el.setProperty( 'type', 'text' );
   },

   toggle: function( el ) {
      var opt         = this.mergeOptions( el.id );
      var replacement = $( el.id + opt.suffix );

      if (el.getProperty( 'disabled' )) return;

      replacement.toggleClass( 'checked' );

      if (replacement.hasClass( 'checked' )) {
         el.setProperty( 'checked', 'checked' );

         if (el.type == 'radio') {
            this.collection.each( function( box_id ) {
               var box = $( box_id ), replacement = $( box_id + opt.suffix );

               if (replacement && box_id != el.id && box.name == el.name
                   && replacement.hasClass( 'checked' )) {
                  replacement.removeClass ( 'checked' );
                  box.removeProperty( 'checked' );
               }
            }, this );
         }
      }
      else el.removeProperty( 'checked' );
   }
} );

var SubmitUtils = new Class( {
   Implements: [ Options ],

   options       : {
      config_attr: 'anchors',
      formName   : null,
      selector   : '.submit',
      wildCards  : [ '%', '*' ]
   },

   initialize: function( options ) {
      this.aroundSetOptions( options );
      this.form = document.forms ? document.forms[ this.options.formName ]
                                 : function() {};
      this.build();
   },

   attach: function( el ) {
      var cfg; if (! (cfg = this.config[ el.id ])) return;

      var event = cfg.event || 'click', key = 'submit:' + event, handler;

      if (! (handler = el.retrieve( key )))
         el.store( key, handler = function( ev ) {
            return this[ cfg.method ].apply( this, cfg.args ) }.bind( this ) );

      el.addEvent( event, handler );
   },

   chooser: function( href, options ) {
      var opt   = this.mergeOptions( options );
      var value = this.form.elements[ opt.field ].value || '';

      for (var i = 0, max = opt.wildCards.length; i < max; i++) {
         if (value.indexOf( opt.wildCards[ i ] ) > -1) {
            var uri = href + '?form=' + opt.formName + '&field='  + opt.field
                                                     + '&button=' + opt.button;

            if (opt.subtype == 'modal') {
               opt.value        = value;
               opt.name         = opt.field;
               opt.onComplete   = function() { this.rebuild() };
               this.modalDialog = this.context.window.modalDialog( uri, opt );
               return false;
            }

            opt.name = 'chooser'; uri += '&val=' + value;
            top.chooser = this.context.window.openWindow( uri, opt );
            top.chooser.opener = top;
            return false;
         }
      }

      return this.submitForm( opt.button );
   },

   clearField: function( field_name ) {
      this.setField( field_name, '' ); return false;
   },

   confirmSubmit: function( button_value, text ) {
      if (text.length < 1 || window.confirm( text ))
         return this.submitForm( button_value );

      return false;
   },

   detach: function( el ) {
      var remove = function( el ) {
         var cfg; if (! (cfg = this.config[ el.id ])) return;

         var event   = cfg.event || 'click', key = 'submit:' + event;
         var handler = el.retrieve( key );

         if (handler) el.removeEvent( event, handler ).eliminate( key );
      }.bind( this );

      if (el) { remove( el ); this.collection.erase( el ) }
      else { this.collection.each( remove ); this.collection = [] }

      return this;
   },

   historyBack: function() {
      window.history.back(); return false;
   },

   postData: function( url, data ) {
      new Request( { url: url } ).post( data ); return false;
   },

   refresh: function( name, value ) {
      if (name) this.context.cookies.set( name, value );

      this.form.submit();
      return false;
   },

   returnValue: function( form_name, field_name, value, button ) {
      if (form_name && field_name) {
         var form = opener ? opener.document.forms[ form_name ]
                           :        document.forms[ form_name ];

         var el; if (form && (el = form.elements[ field_name ])) {
            el.value = value; if (el.focus) el.focus();
         }
      }

      if (opener) window.close();
      else if (this.modalDialog) this.modalDialog.hide();

      if (button) this.submitForm( button );

      return false;
   },

   setField: function( name, value ) {
      var el; if (name && (el = this.form.elements[ name ])) el.value = value;

      return el ? el.value : null;
   },

   submitForm: function( button_value ) {
      if (!button_value) { this.form.submit(); return true; }

      var button; $$( '*[name=_method]' ).some( function( el ) {
         if (el.value == button_value) { button = el; return true }
         return false;
      }.bind( this ) );

      if (button) { this.detach( button ); button.click() }
      else {
         new Element( 'input', {
            name: '_method', type: 'hidden', value: button_value
         } ).inject( $( this.form ) );
      }

      this.form.submit();
      return true;
   },

   submitOnReturn: function( button_value ) {
      ev = new DOMEvent();

      if (ev.key == 'enter') {
         if (document.forms) return this.submitForm( button_value );
         else window.alert( 'Document contains no forms' );
      }

      return false;
   }
} );

/* Description: Class for creating nice tips that follow the mouse cursor
                when hovering an element.
   License: MIT-style license
   Authors: Valerio Proietti, Christoph Pojer, Luis Merino, Peter Flanigan */

(function() {

var getText = function( el ) {
   return (el.get( 'rel' ) || el.get( 'href' ) || '').replace( 'http://', '' );
};

var read = function( el, opt ) {
   return opt ? (typeOf( opt ) == 'function' ? opt( el ) : el.get( opt )) : '';
};

var storeTitleAndText = function( el, opt ) {
   if (el.retrieve( 'tip:title' )) return;

   var title = read( el, opt.title ), text = read( el, opt.text );

   if (title) {
      el.store( 'tip:native', title ); var pair = title.split( opt.separator );

      if (pair.length > 1) {
         title = pair[ 0 ].trim(); text = (pair[ 1 ] + ' ' + text).trim();
      }
   }
   else title = opt.hellip;

   if (title.length > opt.maxTitleChars)
      title = title.substr( 0, opt.maxTitleChars - 1 ) + opt.hellip;

   el.store( 'tip:title', title ).erase( 'title' );
   el.store( 'tip:text',  text  );
};

this.Tips = new Class( {
   Implements: [ Events, Options ],

   options         : {
      className    : 'tips',
      fixed        : false,
      fsWidthRatio : 1.25,
      hellip       : '\u2026',
      hideDelay    : 100,
      id           : 'tips',
      maxTitleChars: 40,
      maxWidthRatio: 4,
      minWidth     : 120,
      offsets      : { x: 4, y: 36 },
/*    onAttach     : function( el ) {}, */
/*    onBound      : function( coords ) {}, */
/*    onDetach     : function( el) {}, */
      onHide       : function( tip, el ) {
         tip.setStyle( 'visibility', 'hidden'  ) },
      onShow       : function( tip, el ) {
         tip.setStyle( 'visibility', 'visible' ) },
      selector     : '.tips',
      separator    : '~',
      showDelay    : 100,
      showMark     : true,
      spacer       : '\u00a0\u00a0\u00a0',
      text         : getText,
      timeout      : 30000,
      title        : 'title',
      windowPadding: { x: 0, y: 0 }
   },

   initialize: function( options ) {
      this.aroundSetOptions( options ); this.createMarkup();

      this.build(); this.fireEvent( 'initialize' );
   },

   attach: function( el ) {
      var opt = this.options; storeTitleAndText( el, opt );

      var events = [ 'enter', 'leave' ]; if (! opt.fixed) events.push( 'move' );

      events.each( function( value ) {
         var key = 'tip:' + value, method = 'element' + value.capitalize();

         var handler; if (! (handler = el.retrieve( key )))
            el.store( key, handler = function( ev ) {
               return this[ method ].apply( this, [ ev, el ] ) }.bind( this ) );

         el.addEvent( 'mouse' + value, handler );
      }, this );

      this.fireEvent( 'attach', [ el ] );
   },

   createMarkup: function() {
      var opt    = this.options;
      var klass  = opt.className;
      var dlist  = this.tip = new Element( 'dl', {
         'id'    : opt.id,
         'class' : klass + '-container',
         'styles': { 'left'      : 0,
                     'position'  : 'absolute',
                     'top'       : 0,
                     'visibility': 'hidden' } } ).inject( $( 'body' ) );

      if (opt.showMark) {
         this.mark = []; [ 0, 1 ].each( function( idx ) {
            var el = this.mark[ idx ] = new Element( 'span', {
               'class': klass + '-mark' + idx } ).inject( dlist );

            [ 'left', 'top' ].each( function( prop ) {
               el.store( 'tip:orig-' + prop, el.getStyle( prop ) ) } );
         }, this );
      }

      this.term = new Element( 'dt', {
         'class' : klass + '-term' } ).inject( dlist );
      this.defn = new Element( 'dd', {
         'class' : klass + '-defn' } ).inject( dlist );
   },

   detach: function() {
      this.collection.each( function( el ) {
         [ 'enter', 'leave', 'move' ].each( function( value ) {
            var ev = 'mouse' + value, key = 'tip:' + value;

            el.removeEvent( ev, el.retrieve( key ) ).eliminate( key );
         } );

         this.fireEvent( 'detach', [ el ] );

         if (this.options.title == 'title') {
            var original = el.retrieve( 'tip:native' );

            if (original) el.set( 'title', original );
         }
      }, this );

      return this;
   },

   elementEnter: function( ev, el ) {
      clearTimeout( this.timer );
      this.timer = this.show.delay( this.options.showDelay, this, el );
      this.setup( el ); this.position( ev, el );
   },

   elementLeave: function( ev, el ) {
      clearTimeout( this.timer );

      var opt = this.options, delay = Math.max( opt.showDelay, opt.hideDelay );

      this.timer = this.hide.delay( delay, this, el );
      this.fireForParent( ev, el );
   },

   elementMove: function( ev, el ) {
      this.position( ev, el );
   },

   fireForParent: function( ev, el ) {
      el = el.getParent(); if (! el || el == document.body) return;

      if (el.retrieve( 'tip:enter' )) el.fireEvent( 'mouseenter', ev );
      else this.fireForParent( ev, el );
   },

   hide: function( el ) {
      this.fireEvent( 'hide', [ this.tip, el ] );
   },

   position: function( ev, el ) {
      var opt    = this.options;
      var bounds = opt.fixed ? this._positionFixed( ev, el )
                             : this._positionVariable( ev, el );

      if (opt.showMark) this._positionMarks( bounds );
   },

   _positionFixed: function( ev, el ) {
      var offsets = this.options.offsets, pos = el.getPosition();

      this.tip.setStyles( { left: pos.x + offsets.x, top: pos.y + offsets.y } );

      return { x: false, x2: false, y: false, y2: false };
   },

   _positionMark: function( state, quads, coord, dimn ) {
      for (var idx = 0; idx < 2; idx++) {
         var el     = this.mark[ idx ];
         var colour = el.getStyle( 'border-' + quads[ 0 ] + '-color' );

         if (colour != 'transparent') {
            el.setStyle( 'border-' + quads[ 0 ] + '-color', 'transparent' );
            el.setStyle( 'border-' + quads[ 1 ] + '-color', colour );
         }

         var orig  = el.retrieve( 'tip:orig-' + coord ).toInt();
         var value = this.tip.getStyle( dimn ).toInt();

         if (coord == 'left') {
            var blsize = this.tip.getStyle( 'border-left' ).toInt();
            var left   = this.mark[ 0 ].retrieve( 'tip:orig-left' ).toInt();

            value -= 2 * left - blsize * idx;
         }

         el.setStyle( coord, (state ? value : orig) + 'px' );
      }
   },

   _positionMarks: function( coords ) {
      var quads = coords[ 'x2' ] ? [ 'left', 'right' ] : [ 'right', 'left' ];

      this._positionMark( coords[ 'x2' ], quads, 'left', 'width' );

      quads = coords[ 'y2' ] ? [ 'bottom', 'top' ] : [ 'top', 'bottom' ];

      this._positionMark( coords[ 'y2' ], quads, 'top', 'height' );
   },

   _positionVariable: function( ev, el ) {
      var opt     = this.options, offsets = opt.offsets, pos = {};
      var prop    = { x: 'left',                 y: 'top'                 };
      var scroll  = { x: window.getScrollLeft(), y: window.getScrollTop() };
      var tip     = { x: this.tip.offsetWidth,   y: this.tip.offsetHeight };
      var win     = { x: window.getWidth(),      y: window.getHeight()    };
      var bounds  = { x: false, x2: false,       y: false, y2: false      };
      var padding = opt.windowPadding;

      for (var z in prop) {
         var coord = ev.page[ z ] + offsets[ z ];

         if (coord < 0) bounds[ z ] = true;

         if (coord + tip[ z ] > scroll[ z ] + win[ z ] - padding[ z ]) {
            coord = ev.page[ z ] - offsets[ z ] - tip[ z ];
            bounds[ z + '2' ] = true;
         }

         pos[ prop[ z ] ] = coord;
      }

      this.fireEvent( 'bound', bounds ); this.tip.setStyles( pos );

      return bounds;
   },

   setup: function( el ) {
      var opt    = this.options;
      var term   = el.retrieve( 'tip:title' ) || '';
      var defn   = el.retrieve( 'tip:text'  ) || '';
      var tfsize = this.term.getStyle( 'font-size' ).toInt();
      var dfsize = this.defn.getStyle( 'font-size' ).toInt();
      var max    = Math.floor( window.getWidth() / opt.maxWidthRatio );
      var w      = Math.max( term.length * tfsize / opt.fsWidthRatio,
                             defn.length * dfsize / opt.fsWidthRatio );

      w = parseInt( w < opt.minWidth ? opt.minWidth : w > max ? max : w );

      this.tip.setStyle( 'width', w + 'px' );
      this.term.empty().appendText( term || opt.spacer );

      if (defn) this.defn.empty().setStyle( 'display', '' ).appendText( defn );
      else this.defn.empty().setStyle( 'display', 'none' );
   },

   show: function( el ) {
      var opt = this.options;

      if (opt.timeout) this.timer = this.hide.delay( opt.timeout, this );

      this.fireEvent( 'show', [ this.tip, el ] );
   }
} );
} )();

var Togglers = new Class( {
   Implements: [ Options ],

   options: { config_attr: 'anchors', selector: '.togglers' },

   initialize: function( options ) {
      this.aroundSetOptions( options ); this.build();

      this.resize = this.context.resize.bind( this.context );
   },

   attach: function( el ) {
      var cfg; if (! (cfg = this.config[ el.id ])) return;

      el.addEvent( cfg.event || 'click', function( ev ) {
         ev.stop(); this[ cfg.method ].apply( this, cfg.args ) }.bind( this ) );
   },

   toggle: function( id, name ) {
      var el = $( id ); if (! el) return;

      var toggler = el.retrieve( name ); if (! toggler) return;

      toggler.toggle( this.context.cookies ); this.resize();
   },

   toggleSwapText: function( id, name, s1, s2 ) {
      var el = $( id ); if (! el) return; var cookies = this.context.cookies;

      if (cookies.get( name ) == 'true') {
         cookies.set( name, 'false' );

         if (el) el.set( 'html', s2 );

         if (el = $( name + 'Disp' )) el.hide();
      }
      else {
         cookies.set( name, 'true' );

         if (el) el.set( 'html', s1 );

         if (el = $( name + 'Disp' )) el.show();
      }

      this.resize();
   }
} );

var WindowUtils = new Class( {
   Implements: [ Options, LoadMore ],

   options       : {
      config_attr: 'anchors',
      customLogFn: false,
      height     : 600,
      maskOpts   : {},
      quiet      : false,
      selector   : '.windows',
      target     : null,
      url        : null,
      width      : 800
   },

   initialize: function( options ) {
      this.aroundSetOptions( options ); var opt = this.options;

      if (opt.customLogFn) {
         if (typeOf( opt.customLogFn ) != 'function')
            throw 'customLogFn is not a function';
         else this.customLogFn = opt.customLogFn;
      }

      [ 'log', 'warn' ].each( function( method ) {
         var old = console[ method ];

         console[ method ] = function() {
            var stack = ( new Error() ).stack.split( /\n/ );

            // Chrome includes a single "Error" line, FF doesn't.
            if (stack[ 0 ].indexOf( 'Error' ) === 0) stack = stack.slice( 1 );

            var args = [].slice.apply( arguments )
                               .concat( [ stack[ 3 ].trim() ] );

            return old.apply( console, args );
         };
      } );

      if (opt.target == 'top') this.placeOnTop();

      this.dialogs = [];
      this.build();
   },

   location: function( href ) {
      if (document.images) top.location.replace( href );
      else top.location.href = href;
   },

   logger: function( message ) {
      if (this.options.quiet) return;

      if (this.customLogFn) { this.customLogFn( message ) }
      else if (window.console && window.console.log) {
         window.console.log( message );
      }
   },

   modalDialog: function( href, options ) {
      var opt = this.mergeOptions( options ), id = opt.name + '_dialog', dialog;

      if (! (dialog = this.dialogs[ opt.name ])) {
         var content = new Element( 'div', {
            'id': id } ).appendText( 'Loading...' );
         var win     = window.getScrollSize();

         opt.maskOpts.id     = 'mask-' + opt.name;
         opt.maskOpts.height = window.getHeight();
         opt.maskOpts.width  = window.getWidth();
         dialog = this.dialogs[ opt.name ]
                = new Dialog( undefined, content, opt );
      }

      this.request( href, id, opt.value || '', opt.onComplete || function() {
         this.rebuild(); dialog.show() } );

      return dialog;
   },

   openWindow: function( href, options ) {
      return new Browser.Popup( href, this.mergeOptions( options ) );
   },

   placeOnTop: function() {
      if (self != top) {
         if (document.images) top.location.replace( window.location.href );
         else top.location.href = window.location.href;
      }
   }
} );
