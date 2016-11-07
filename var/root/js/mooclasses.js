// Perl Artistic license except where stated otherwise

Date.defineParser( '%d/%m/%Y @ %H:%M' );

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

      return Number.convert( met_day_fraction ).format( { decimals: 2 } );
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
      useMask : true
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

var DropMenu = new Class( {
   Implements: [ Options, Events ],

   options: {
      closeDelay: 200,
      itemSelector: 'li',
      listSelector: 'ul',
      onClose: function( el ) {
         var selector = this.options.itemSelector;

         if (!el.getParent( selector ).hasClass( 'open' )) el.hide();
      },
      onInitialize: function( el ) {
         var selector = this.options.itemSelector;

         if (!el.getParent( selector ).hasClass( 'open' )
             && !el.hasClass( 'menu' )) el.hide();
      },
      onOpen: function( el ) { el.show(); },
      openDelay: 0,
      selector: '.dropmenu',
      toggleSelector: 'span'
   },

   initialize: function( options ) {
      this.aroundSetOptions( options ); this.build();
   },

   attach: function( menu ) {
      var opts = this.options;
      var selector = opts.itemSelector + ' > ' + opts.listSelector;

      menu.getElements( selector ).each( function( el ) {
         var parent = el.getParent( opts.itemSelector ), timer;
         var child  = parent.getFirst( opts.toggleSelector );

         this.fireEvent( 'initialize', el );

         child.addEvent( 'click', function( ev ) {
            ev.stop(); clearTimeout( timer );

            if (parent.retrieve( 'DropDownOpen' )) {
               parent.store( 'DropDownOpen', false );

               if (opts.closeDelay) {
                  timer = this.fireEvent.delay
                     ( opts.closeDelay, this, [ 'close', el ] );
               }
               else this.fireEvent( 'close', el );
            }
            else {
               parent.store( 'DropDownOpen', true );

               if (opts.openDelay) {
                  timer = this.fireEvent.delay
                     ( opts.openDelay, this, [ 'open', el ] );
               }
               else this.fireEvent( 'open', el );
            }
         }.bind( this ) );
      }, this );
   }
} );

/* Description: An Fx.Elements extension which allows you to easily
 *              create accordion type controls.
 * License: MIT-style license
 * Authors: Valerio Proietti, Peter Flanigan */

Fx.Accordion = new Class( {
   Extends: Fx.Elements,

   options               : {
      alwaysHide        : false,
      display           : 0,
      fixedHeight       : false,
      fixedWidth        : false,
      height            : true,
      initialDisplayFx  : true,
/*    onActive          : function( togglers, index, section ) {}, */
/*    onBackground      : function( togglers, index, section ) {}, */
      opacity           : true,
      returnHeightToAuto: true,
      show              : false,
      trigger           : 'click',
      wait              : false,
      width             : false
   },

   initialize: function() {
      var defined = function( obj ) { return obj != null };
      var params  = Array.link( arguments, {
         'options'  : Type.isObject,
         'togglers' : defined,
         'elements' : defined
      } );

      this.parent( params.elements, params.options );
      this.togglers      = $$( params.togglers );
      this.internalChain = new Chain();
      this.previous      = -1;
      this.effects       = {};

      var opt = this.options;

      if (opt.alwaysHide) opt.wait = true;

      if (opt.show || opt.show === 0) {
         opt.display = false; this.previous = opt.show;
      }

      if (opt.opacity) this.effects.opacity = 'fullOpacity';

      if (opt.width) this.effects.width = opt.fixedWidth ? 'fullWidth'
                                                         : 'offsetWidth';

      if (opt.height) this.effects.height = opt.fixedHeight ? 'fullHeight'
                                                            : 'scrollHeight';

      for (var i = 0, l = this.togglers.length; i < l; i++) {
         var toggler = this.togglers[ i ];

         if (i == 0) toggler.addClass( 'accordion_header_first' );

         this.addSection( toggler, this.elements[ i ] );
      }

      this.elements.each( function( el, i ) {
         if (opt.show === i) {
            this.fireEvent( 'active', [ this.togglers, i, el ] );
         }
         else {
            for (var fx in this.effects) el.setStyle( fx, 0 );
         }
      }, this );

      if (opt.display || opt.display === 0)
         this.display( opt.display, opt.initialDisplayFx );

      this.addEvent( 'complete',
                     this.internalChain.callChain.bind( this.internalChain ) );
   },

   addSection: function( toggler, el ) {
      toggler = document.id( toggler ); el = document.id( el );

      var test = this.togglers.contains( toggler );

      this.togglers.include( toggler ); this.elements.include( el );

      var opt       = this.options;
      var index     = this.togglers.indexOf( toggler );
      var displayer = this.display.pass( [ index, true ], this );

      toggler.addEvent( opt.trigger, displayer );
      toggler.store( 'accordion:display', displayer );
      el.setStyle( 'overflow-y', opt.fixedHeight ? 'auto' : 'hidden' );
      el.setStyle( 'overflow-x', opt.fixedWidth  ? 'auto' : 'hidden' );
      el.fullOpacity = 1;

      if (! test) { for (var fx in this.effects) el.setStyle( fx, 0 ); }

      this.internalChain.chain( function() {
         if (! opt.fixedHeight && opt.returnHeightToAuto
             && ! this.selfHidden) {
            if (this.now == index) el.setStyle( 'height', 'auto' );
         };
      }.bind( this ) );

      return this;
   },

   detach: function( toggler ) {
      var remove = function( toggler ) {
         toggler.removeEvent( this.options.trigger,
                              toggler.retrieve( 'accordion:display' ) );
      }.bind( this );

      if (! toggler) this.togglers.each( remove );
      else remove( toggler );

      return this;
   },

   display: function( index, useFx ) {
      if (! this.check( index, useFx )) return this;

      var els = this.elements, opt = this.options;

      index = (typeOf( index ) == 'element') ? els.indexOf( index )
                                             : index;
      index = index >= els.length ? els.length - 1 : index;
      useFx = useFx != null ? useFx : true;

      if (! opt.fixedHeight && opt.returnHeightToAuto) {
         var prev = this.previous > -1 ? els[ this.previous ] : false;

         if (prev && ! this.selfHidden) {
            for (var fx in this.effects) {
               prev.setStyle( fx, prev[ this.effects[ fx ] ] );
            }
         }
      }

      if (this.timer && opt.wait) return this;

      this.previous = this.now != undefined ? this.now : -1;
      this.now      = index;

      var obj = this._element_iterator( function( el, i, hide ) {
         this.fireEvent( hide ? 'background' : 'active',
                         [ this.togglers, i, el ] );
      }.bind( this ) );

      return useFx ? this.start( obj ) : this.set( obj );
   },

   _element_iterator: function( f ) {
      var obj = {}, opt = this.options;

      this.elements.each( function( el, i ) {
         var hide = false; obj[ i ] = {};

         if (i != this.now) { hide = true }
         else if (opt.alwaysHide && ((el.offsetHeight > 0 && opt.height)
                                   || el.offsetWidth  > 0 && opt.width)) {
            hide = this.selfHidden = true;
         }

         f( el, i, hide );

         for (var fx in this.effects)
            obj[ i ][ fx ] = hide ? 0 : el[ this.effects[ fx ] ];
      }, this );

      return obj;
   },

   removeSection: function( toggler, displayIndex ) {
      var index   = this.togglers.indexOf( toggler );
      var el      = this.elements[ index ];
      var remover = function() {
         this.togglers.erase( toggler );
         this.elements.erase( el );
         this.detach( toggler );
      }.bind( this );

      if (this.now == index || displayIndex != null){
         this.display( displayIndex != null ? displayIndex
                       : (index - 1 >= 0 ? index - 1 : 0) ).chain( remover );
      }
      else { remover() }

      return this;
   },

   resize: function() {
      var opt    = this.options;
      var height = typeOf( opt.fixedHeight ) == 'function'
                 ? opt.fixedHeight.call() : opt.fixedHeight;
      var width  = typeOf( opt.fixedWidth  ) == 'function'
                 ? opt.fixedWidth.call()  : opt.fixedWidth;
      var obj    = this._element_iterator( function( el, i, hide ) {
         if (height) el.fullHeight = height;
         if (width)  el.fullWidth  = width;
      }.bind( this ) );

      this.set( obj );
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
      if (url.substring( 0, 4 ) != 'http') url = this.options.url + url;

      new Request.JSON( { onSuccess: this._response( on_complete ), url: url } )
                  .get( { 'id': id, 'val': val } );
   },

   _response: function( on_complete ) {
      return function( resp ) {
         if (resp.id) $( resp.id ).set( 'html', resp.html );

         if (resp.script) Browser.exec( resp.script );

         if (on_complete) on_complete.call( this.context, resp );
      }.bind( this );
   }
} );

var Navigation = new Class( {
   Implements: [ Options ],

   options         : {
      config_attr  : 'sidebars',
      panel        : 0,
      panelClass   : '.nav-panel',
      reset        : false,
      selector     : 'navigation',
      togglerClass : '.aj-nav'
   },

   initialize: function( options ) {
      this.config  = options.config; delete options[ 'config'  ];
      this.context = options.context || {}; delete options[ 'context' ];

      this.setOptions( options );

      var opt = this.options, selector = opt.selector;

      if (!this.config && opt.config_attr)
         this.config = this.context.config[ opt.config_attr ];

      if (!this.config) this.config = {};

      var sb; if (! (sb = this.el = $( selector ))) return;

      var cookies   = this.context.cookies || {};
      var sb_panel  = cookies.get( selector + 'Panel' ) || opt.panel;
      var togglers  = $$( opt.togglerClass ), panels = $$( opt.panelClass );

      if (this.config.navigation_reset) { sb_panel = opt.panel }

      // Create an Accordion widget in the side bar
      this.accordion = new Fx.Accordion( togglers, panels, {
         display      : sb_panel,
         opacity      : false,
         onActive     : function( togglers, index, el ) {
            var toggler = togglers[ index ];

            toggler.swapClass( 'inactive', 'active' );
            this.context.cookies.set( selector + 'Panel', index );

            var cfg; if (! (cfg = this.config[ toggler.id ])) return;

            if (cfg.action && cfg.name) {
               this.context.server.request( cfg.action, cfg.name,
                                            cfg.value,  cfg.onComplete );
            }
         }.bind( this ),
         onBackground : function( togglers, index, el ) {
            togglers[ index ].swapClass( 'active', 'inactive' );
         }
      } );

      return;
   },

   reset: function() {
      var opt = this.options;

      this.context.cookies.set( opt.selector + 'Panel', opt.panel );
      return;
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
         new Element( 'div', { 'class': klass } ).inject( $( 'body' ) );

      this.queue = [];
   },

   create: function( content, options ) { // Create new notification and show
      var opt  = this.mergeOptions( options );
      var qlen = this.board.getChildren( '.notice:not(.hiding)' ).length;

      if (opt.limit && qlen >= opt.limit) { // Limit reached
         if (opt.queue) this.queue.push( [ content, opt ] );
         return;
      }

      var el = new Element( 'div', { 'class': 'notice' } ).set( 'html', content );

      if (opt.canClose) {
         new Element( 'div', { 'class': 'close-icon' } ).inject( el, 'top' );
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

/* name: Picker
 * description: Creates a Picker, which can be used for anything
 * authors: Arian Stolwijk
 * requires: [Core/Element.Dimensions, Core/Fx.Tween, Core/Fx.Transitions]
 * provides: Picker */

var Picker = new Class( {
   Implements: [ Options, Events ],

   options: {/*
      onShow: function(){},
      onOpen: function(){},
      onHide: function(){},
      onClose: function(){},*/
      pickerClass: 'datepicker',
      inject: null,
      animationDuration: 400,
      useFadeInOut: true,
      positionOffset: {x: 0, y: 0},
      pickerPosition: 'bottom',
      draggable: true,
      showOnInit: true,
      columns: 1,
      footer: false
   },

   initialize: function(options){
      this.setOptions(options);
      this.constructPicker();
      if (this.options.showOnInit) this.show();
   },

   constructPicker: function(){
      var options = this.options;

      var picker = this.picker = new Element('div', {
         'class': options.pickerClass,
         styles: {
            left: 0,
            top: 0,
            display: 'none',
            opacity: 0
         }
      }).inject(options.inject || document.body);
      picker.addClass('column_' + options.columns);

      if (options.useFadeInOut){
         picker.set('tween', {
            duration: options.animationDuration,
            link: 'cancel'
         });
      }

      // Build the header
      var header = this.header = new Element('div.header').inject(picker);

      var title = this.title = new Element('div.title').inject(header);
      var titleID = this.titleID = 'pickertitle-' + String.uniqueID();
      this.titleText = new Element('div', {
         'role': 'heading',
         'class': 'titleText',
         'id': titleID,
         'aria-live': 'assertive',
         'aria-atomic': 'true'
      }).inject(title);

      this.closeButton = new Element('div.closeButton[text=x][role=button]')
         .addEvent('click', this.close.pass(false, this))
         .inject(header);

      // Build the body of the picker
      var body = this.body = new Element('div.body').inject(picker);

      if (options.footer){
         this.footer = new Element('div.footer').inject(picker);
         picker.addClass('footer');
      }

      // oldContents and newContents are used to slide from the old content to a new one.
      var slider = this.slider = new Element('div.dp_slider', {
         styles: {
            position: 'absolute',
            top: 0,
            left: 0
         }
      }).set('tween', {
         duration: options.animationDuration,
         transition: Fx.Transitions.Quad.easeInOut
      }).inject(body);

      this.newContents = new Element('div', {
         styles: {
            position: 'absolute',
            top: 0,
            left: 0
         }
      }).inject(slider);

      this.oldContents = new Element('div', {
         styles: {
            position: 'absolute',
            top: 0
         }
      }).inject(slider);

      this.originalColumns = options.columns;
      this.setColumns(options.columns);

      // IFrameShim for select fields in IE
      var shim = this.shim = window['IframeShim'] ? new IframeShim(picker) : null;

      // Dragging
      if (options.draggable && typeOf(picker.makeDraggable) == 'function'){
         this.dragger = picker.makeDraggable(shim ? {
            onDrag: shim.position.bind(shim)
         } : null);
         picker.setStyle('cursor', 'move');
      }
   },

   open: function(noFx){
      if (this.opened == true) return this;
      this.opened = true;
      var self = this,
         picker = this.picker.setStyle('display', 'block').set('aria-hidden', 'false')
      if (this.shim) this.shim.show();
      this.fireEvent('open');
      if (this.options.useFadeInOut && !noFx){
         picker.get('tween').start('opacity', 1).chain(function(){
            self.fireEvent('show');
            this.callChain();
         });
      } else {
         picker.setStyle('opacity', 1);
         this.fireEvent('show');
      }
      return this;
   },

   show: function(){
      return this.open(true);
   },

   close: function(noFx){
      if (this.opened == false) return this;
      this.opened = false;
      this.fireEvent('close');
      var self = this, picker = this.picker, hide = function(){
         picker.setStyle('display', 'none').set('aria-hidden', 'true');
         if (self.shim) self.shim.hide();
         self.fireEvent('hide');
      };
      if (this.options.useFadeInOut && !noFx){
         picker.get('tween').start('opacity', 0).chain(hide);
      } else {
         picker.setStyle('opacity', 0);
         hide();
      }
      return this;
   },

   hide: function(){
      return this.close(true);
   },

   toggle: function(){
      return this[this.opened == true ? 'close' : 'open']();
   },

   destroy: function(){
      this.picker.destroy();
      if (this.shim) this.shim.destroy();
   },

   position: function(x, y){
      var offset = this.options.positionOffset,
         scroll = document.getScroll(),
         size = document.getSize(),
         pickersize = this.picker.getSize();

      if (typeOf(x) == 'element'){
         var element = x,
            where = y || this.options.pickerPosition;

         var elementCoords = element.getCoordinates();

         x = (where == 'left') ? elementCoords.left - pickersize.x
            : (where == 'bottom' || where == 'top') ? elementCoords.left
            : elementCoords.right
         y = (where == 'bottom') ? elementCoords.bottom
            : (where == 'top') ? elementCoords.top - pickersize.y
            : elementCoords.top;
      }

      x += offset.x * ((where && where == 'left') ? -1 : 1);
      y += offset.y * ((where && where == 'top') ? -1: 1);

      if ((x + pickersize.x) > (size.x + scroll.x)) x = (size.x + scroll.x) - pickersize.x;
      if ((y + pickersize.y) > (size.y + scroll.y)) y = (size.y + scroll.y) - pickersize.y;
      if (x < 0) x = 0;
      if (y < 0) y = 0;

      this.picker.setStyles({
         left: x,
         top: y
      });
      if (this.shim) this.shim.position();
      return this;
   },

   setBodySize: function(){
      var bodysize = this.bodysize = this.body.getSize();

      this.slider.setStyles({
         width: 2 * bodysize.x,
         height: bodysize.y
      });
      this.oldContents.setStyles({
         left: bodysize.x,
         width: bodysize.x,
         height: bodysize.y
      });
      this.newContents.setStyles({
         width: bodysize.x,
         height: bodysize.y
      });
   },

   setColumnContent: function(column, content){
      var columnElement = this.columns[column];
      if (!columnElement) return this;

      var type = typeOf(content);
      if (['string', 'number'].contains(type)) columnElement.set('text', content);
      else columnElement.empty().adopt(content);

      return this;
   },

   setColumnsContent: function(content, fx){
      var old = this.columns;
      this.columns = this.newColumns;
      this.newColumns = old;

      content.forEach(function(_content, i){
         this.setColumnContent(i, _content);
      }, this);
      return this.setContent(null, fx);
   },

   setColumns: function(columns){
      var _columns = this.columns = new Elements, _newColumns = this.newColumns = new Elements;
      for (var i = columns; i--;){
         _columns.push(new Element('div.column').addClass('column_' + (columns - i)));
         _newColumns.push(new Element('div.column').addClass('column_' + (columns - i)));
      }

      var oldClass = 'column_' + this.options.columns, newClass = 'column_' + columns;
      this.picker.removeClass(oldClass).addClass(newClass);

      this.options.columns = columns;
      return this;
   },

   setContent: function(content, fx){
      if (content) return this.setColumnsContent([content], fx);

      // swap contents so we can fill the newContents again and animate
      var old = this.oldContents;
      this.oldContents = this.newContents;
      this.newContents = old;
      this.newContents.empty();

      this.newContents.adopt(this.columns);

      this.setBodySize();

      if (fx){
         this.fx(fx);
      } else {
         this.slider.setStyle('left', 0);
         this.oldContents.setStyles({left: 0, opacity: 0});
         this.newContents.setStyles({left: 0, opacity: 1});
      }
      return this;
   },

   fx: function(fx){
      var oldContents = this.oldContents,
         newContents = this.newContents,
         slider = this.slider,
         bodysize = this.bodysize;
      if (fx == 'right'){
         oldContents.setStyles({left: 0, opacity: 1});
         newContents.setStyles({left: bodysize.x, opacity: 1});
         slider.setStyle('left', 0).tween('left', 0, -bodysize.x);
      } else if (fx == 'left'){
         oldContents.setStyles({left: bodysize.x, opacity: 1});
         newContents.setStyles({left: 0, opacity: 1});
         slider.setStyle('left', -bodysize.x).tween('left', -bodysize.x, 0);
      } else if (fx == 'fade'){
         slider.setStyle('left', 0);
         oldContents.setStyle('left', 0).set('tween', {
            duration: this.options.animationDuration / 2
         }).tween('opacity', 1, 0).get('tween').chain(function(){
            oldContents.setStyle('left', bodysize.x);
         });
         newContents.setStyles({opacity: 0, left: 0}).set('tween', {
            duration: this.options.animationDuration
         }).tween('opacity', 0, 1);
      }
   },

   toElement: function(){
      return this.picker;
   },

   setTitle: function(content, fn){
      if (!fn) fn = Function.convert;
      this.titleText.empty().adopt(
         Array.convert(content).map(function(item, i){
            return typeOf(item) == 'element'
               ? item
               : new Element('div.column', {text: fn(item, this.options)}).addClass('column_' + (i + 1));
         }, this)
      );
      return this;
   },

   setTitleEvent: function(fn){
      this.titleText.removeEvents('click');
      if (fn) this.titleText.addEvent('click', fn);
      this.titleText.setStyle('cursor', fn ? 'pointer' : '');
      return this;
   }
} );

/* name: Picker.Attach
 * description: Adds attach and detach methods to the Picker, to attach
 *              it to element events
 * authors: Arian Stolwijk
 * requires: [Picker, Core/Element.Event]
 * provides: Picker.Attach */

Picker.Attach = new Class( {
   Extends: Picker,

   options: {
/*    onAttached: function(event){},
      toggleElements: null, // deprecated
      toggle: null, // When set it deactivate toggling by clicking the input */
      togglesOnly: true, // set to false to always make calendar popup on input element, if true, it depends on the toggles elements set.
      showOnInit: false, // overrides the Picker option
      blockKeydown: true
   },

   initialize: function(attachTo, options){
      this.parent(options);

      this.attachedEvents = [];
      this.attachedElements = [];
      this.toggles = [];
      this.inputs = [];

      var documentEvent = function(event){
         if (this.attachedElements.contains(event.target)) return;
         this.close();
      }.bind(this);
      var document = this.picker.getDocument().addEvent('click', documentEvent);

      var preventPickerClick = function(event){
         event.stopPropagation();
         return false;
      };
      this.picker.addEvent('click', preventPickerClick);

      // Support for deprecated toggleElements
      if (this.options.toggleElements) this.options.toggle = document.getElements(this.options.toggleElements);

      this.attach(attachTo, this.options.toggle);
   },

   attach: function(attachTo, toggle){
      if (typeOf(attachTo) == 'string') attachTo = document.id(attachTo);
      if (typeOf(toggle) == 'string') toggle = document.id(toggle);

      var elements = Array.convert(attachTo),
         toggles = Array.convert(toggle),
         allElements = [].append(elements).combine(toggles),
         self = this;

      var closeEvent = function(event){
         var stopInput = self.options.blockKeydown
               && event.type == 'keydown'
               && !(['tab', 'esc'].contains(event.key)),
            isCloseKey = event.type == 'keydown'
               && (['tab', 'esc'].contains(event.key)),
            isA = event.target.get('tag') == 'a';

         if (stopInput || isA) event.preventDefault();
         if (isCloseKey || isA) self.close();
      };

      var getOpenEvent = function(element){
         return function(event){
            var tag = event.target.get('tag');
            if (tag == 'input' && event.type == 'click' && !element.match(':focus') || (self.opened && self.input == element)) return;
            if (tag == 'a') event.stop();
            self.position(element);
            self.open();
            self.fireEvent('attached', [event, element]);
         };
      };

      var getToggleEvent = function(open, close){
         return function(event){
            if (self.opened) close(event);
            else open(event);
         };
      };

      allElements.each(function(element){

         // The events are already attached!
         if (self.attachedElements.contains(element)) return;

         var events = {},
            tag = element.get('tag'),
            openEvent = getOpenEvent(element),
            // closeEvent does not have a depency on element
            toggleEvent = getToggleEvent(openEvent, closeEvent);

         if (tag == 'input'){
            // Fix in order to use togglers only
            if (!self.options.togglesOnly || !toggles.length){
               events = {
                  focus: openEvent,
                  click: openEvent,
                  keydown: closeEvent
               };
            }
            self.inputs.push(element);
         } else {
            if (toggles.contains(element)){
               self.toggles.push(element);
               events.click = toggleEvent
            } else {
               events.click = openEvent;
            }
         }
         element.addEvents(events);
         self.attachedElements.push(element);
         self.attachedEvents.push(events);
      });
      return this;
   },

   detach: function(attachTo, toggle){
      if (typeOf(attachTo) == 'string') attachTo = document.id(attachTo);
      if (typeOf(toggle) == 'string') toggle = document.id(toggle);

      var elements = Array.convert(attachTo),
         toggles = Array.convert(toggle),
         allElements = [].append(elements).combine(toggles),
         self = this;

      if (!allElements.length) allElements = self.attachedElements;

      allElements.each(function(element){
         var i = self.attachedElements.indexOf(element);
         if (i < 0) return;

         var events = self.attachedEvents[i];
         element.removeEvents(events);
         delete self.attachedEvents[i];
         delete self.attachedElements[i];

         var toggleIndex = self.toggles.indexOf(element);
         if (toggleIndex != -1) delete self.toggles[toggleIndex];

         var inputIndex = self.inputs.indexOf(element);
         if (toggleIndex != -1) delete self.inputs[inputIndex];
      });
      return this;
   },

   destroy: function(){
      this.detach();
      return this.parent();
   }
} );

/* name: Locale.en-GB.DatePicker
 * description: English Language File for DatePicker
 * authors: Lazarus Long
 * requires: [More/Locale]
 * provides: Locale.en-GB.DatePicker */

Locale.define( 'en-GB', 'DatePicker', {
   select_a_time      : 'Select a time',
   use_mouse_wheel    : 'Use the mouse wheel to quickly change value',
   time_confirm_button: 'OK',
   apply_range        : 'Apply',
   cancel             : 'Cancel',
   week               : 'Wk.'
} );

/* name: Picker.Date
 * description: Creates a DatePicker, can be used for picking years/months/days
 *              and time, or all of them
 * authors: Arian Stolwijk
 * requires: [Picker, Picker.Attach, Locale.en-US.DatePicker,
 *            More/Locale, More/Date]
 * provides: Picker.Date */

(function() {
this.DatePicker = Picker.Date = new Class( {
   Extends: Picker.Attach,

   options: {
/*    onSelect: function(date){},
      minDate: new Date('3/4/2010'), // Date object or a string
      maxDate: new Date('3/4/2011'), // same as minDate
      availableDates: {}, //
      invertAvailable: false,
      format: null,*/
      timePicker: false,
      timePickerOnly: false, // deprecated, use onlyView = 'time'
      timeWheelStep: 1, // 10,15,20,30
      yearPicker: true,
      yearsPerPage: 20,
      startDay: 1, // Sunday (0) through Saturday (6) - be aware that this may affect your layout, since the days on the right might have a different margin
      rtl: false,
      startView: 'days', // allowed values: {time, days, months, years}
      openLastView: false,
      pickOnly: false, // 'years', 'months', 'days', 'time'
      canAlwaysGoUp: ['months', 'days'],
      updateAll : false, //whether or not to update all inputs when selecting a date
      weeknumbers: false,
      // if you like to use your own translations
      months_abbr: null,
      days_abbr: null,
      years_title: function(date, options){
         var year = date.get('year');
         return year + '-' + (year + options.yearsPerPage - 1);
      },
      months_title: function(date, options){
         return date.get('year');
      },
      days_title: function(date, options){
         return date.format('%b %Y');
      },
      time_title: function(date, options){
         return (options.pickOnly == 'time') ? Locale.get('DatePicker.select_a_time') : date.format('%d %B, %Y');
      }
   },

   initialize: function(attachTo, options){
      this.parent(attachTo, options); this.setOptions(options);

      options = this.options;

      // If we only want to use one picker / backwards compatibility
      ['year', 'month', 'day', 'time'].some(function(what){
         if (options[what + 'PickerOnly']){
            options.pickOnly = what;
            return true;
         }
         return false;
      });
      if (options.pickOnly){
         options[options.pickOnly + 'Picker'] = true;
         options.startView = options.pickOnly;
      }

      // backward compatibility for startView
      var newViews = ['days', 'months', 'years'];
      ['month', 'year', 'decades'].some(function(what, i){
         return (options.startView == what) && (options.startView = newViews[i]);
      });

      options.canAlwaysGoUp = options.canAlwaysGoUp ? Array.convert(options.canAlwaysGoUp) : [];

      // Set the min and max dates as Date objects
      if (options.minDate){
         if (!(options.minDate instanceof Date)) options.minDate = Date.parse(options.minDate);
         options.minDate.clearTime();
      }
      if (options.maxDate){
         if (!(options.maxDate instanceof Date)) options.maxDate = Date.parse(options.maxDate);
         options.maxDate.clearTime();
      }

      if (!options.format){
         options.format = (options.pickOnly != 'time') ? Locale.get('Date.shortDate') : '';
         if (options.timePicker) options.format = (options.format) + (options.format ? ' ' : '') + Locale.get('Date.shortTime');
      }

      // Some link or input has fired an event!
      this.addEvent('attached', function(event, element){
         // This is where we store the selected date
         if (!this.currentView || !options.openLastView)
            this.currentView = options.startView;

         this.date = limitDate(new Date(), options.minDate, options.maxDate);
         var tag = element.get('tag'), input;
         if (tag == 'input') input = element;
         else {
            var index = this.toggles.indexOf(element);
            if (this.inputs[index]) input = this.inputs[index];
         }
         this.getInputDate(input);
         this.input = input;
         this.setColumns(this.originalColumns);
      }.bind(this), true);

   },

   getInputDate: function(input){
      this.date = new Date(); if (!input) return;

      var date = Date.parse( input.get( 'value' ) );

      if (date == null || !date.isValid()){
         var storeDate = input.retrieve( 'datepicker:value' );

         if (storeDate) date = Date.parse( storeDate );
      }

      if (date != null && date.isValid()) this.date = date;
   },

   // Control the previous and next elements

   constructPicker: function(){
      this.parent();

      if (!this.options.rtl){
         this.previous = new Element('div.previous[html=&#171;]').inject(this.header);
         this.next = new Element('div.next[html=&#187;]').inject(this.header);
      } else {
         this.next = new Element('div.previous[html=&#171;]').inject(this.header);
         this.previous = new Element('div.next[html=&#187;]').inject(this.header);
      }
   },

   hidePrevious: function(_next, _show){
      this[_next ? 'next' : 'previous'].setStyle('display', _show ? 'block' : 'none');
      return this;
   },

   showPrevious: function(_next){
      return this.hidePrevious(_next, true);
   },

   setPreviousEvent: function(fn, _next){
      this[_next ? 'next' : 'previous'].removeEvents('click');
      if (fn) this[_next ? 'next' : 'previous'].addEvent('click', fn);
      return this;
   },

   hideNext: function(){
      return this.hidePrevious(true);
   },

   showNext: function(){
      return this.showPrevious(true);
   },

   setNextEvent: function(fn){
      return this.setPreviousEvent(fn, true);
   },

   setColumns: function(columns, view, date, viewFx){
      var ret = this.parent(columns), method;

      if ((view || this.currentView)
         && (method = 'render' + (view || this.currentView).capitalize())
         && this[method]
      ) this[method](date || this.date.clone(), viewFx);

      return ret;
   },

   // Render the Pickers

   renderYears: function(date, fx){
      var options = this.options, pages = options.columns, perPage = options.yearsPerPage,
         _columns = [], _dates = [];
      this.dateElements = [];

      // start neatly at interval (eg. 1980 instead of 1987)
      date = date.clone().decrement('year', date.get('year') % perPage);

      var iterateDate = date.clone().decrement('year', Math.floor((pages - 1) / 2) * perPage);

      for (var i = pages; i--;){
         var _date = iterateDate.clone();
         _dates.push(_date);
         _columns.push(renderers.years(
            timesSelectors.years(options, _date.clone()),
            options,
            this.date.clone(),
            this.dateElements,
            function(date){
               if (options.pickOnly == 'years') this.select(date);
               else this.renderMonths(date, 'fade');
               this.date = date;
            }.bind(this)
         ));
         iterateDate.increment('year', perPage);
      }

      this.setColumnsContent(_columns, fx);
      this.setTitle(_dates, options.years_title);

      // Set limits
      var limitLeft = (options.minDate && date.get('year') <= options.minDate.get('year')),
         limitRight = (options.maxDate && (date.get('year') + options.yearsPerPage) >= options.maxDate.get('year'));
      this[(limitLeft ? 'hide' : 'show') + 'Previous']();
      this[(limitRight ? 'hide' : 'show') + 'Next']();

      this.setPreviousEvent(function(){
         this.renderYears(date.decrement('year', perPage), 'left');
      }.bind(this));

      this.setNextEvent(function(){
         this.renderYears(date.increment('year', perPage), 'right');
      }.bind(this));

      // We can't go up!
      this.setTitleEvent(null);

      this.currentView = 'years';
   },

   renderMonths: function(date, fx){
      var options = this.options, years = options.columns, _columns = [], _dates = [],
         iterateDate = date.clone().decrement('year', Math.floor((years - 1) / 2));
      this.dateElements = [];

      for (var i = years; i--;){
         var _date = iterateDate.clone();
         _dates.push(_date);
         _columns.push(renderers.months(
            timesSelectors.months(options, _date.clone()),
            options,
            this.date.clone(),
            this.dateElements,
            function(date){
               if (options.pickOnly == 'months') this.select(date);
               else this.renderDays(date, 'fade');
               this.date = date;
            }.bind(this)
         ));
         iterateDate.increment('year', 1);
      }

      this.setColumnsContent(_columns, fx);
      this.setTitle(_dates, options.months_title);

      // Set limits
      var year = date.get('year'),
         limitLeft = (options.minDate && year <= options.minDate.get('year')),
         limitRight = (options.maxDate && year >= options.maxDate.get('year'));
      this[(limitLeft ? 'hide' : 'show') + 'Previous']();
      this[(limitRight ? 'hide' : 'show') + 'Next']();

      this.setPreviousEvent(function(){
         this.renderMonths(date.decrement('year', years), 'left');
      }.bind(this));

      this.setNextEvent(function(){
         this.renderMonths(date.increment('year', years), 'right');
      }.bind(this));

      var canGoUp = options.yearPicker && (options.pickOnly != 'months' || options.canAlwaysGoUp.contains('months'));
      var titleEvent = (canGoUp) ? function(){
         this.renderYears(date, 'fade');
      }.bind(this) : null;
      this.setTitleEvent(titleEvent);

      this.currentView = 'months';
   },

   renderDays: function(date, fx){
      var options = this.options, months = options.columns, _columns = [], _dates = [],
         iterateDate = date.clone().decrement('month', Math.floor((months - 1) / 2));
      this.dateElements = [];

      for (var i = months; i--;){
         _date = iterateDate.clone();
         _dates.push(_date);
         _columns.push(renderers.days(
            timesSelectors.days(options, _date.clone()),
            options,
            this.date.clone(),
            this.dateElements,
            function(date){
               if (options.pickOnly == 'days' || !options.timePicker) this.select(date)
               else this.renderTime(date, 'fade');
               this.date = date;
            }.bind(this)
         ));
         iterateDate.increment('month', 1);
      }

      this.setColumnsContent(_columns, fx);
      this.setTitle(_dates, options.days_title);

      var yearmonth = date.format('%Y%m').toInt(),
         limitLeft = (options.minDate && yearmonth <= options.minDate.format('%Y%m')),
         limitRight = (options.maxDate && yearmonth >= options.maxDate.format('%Y%m'));
      this[(limitLeft ? 'hide' : 'show') + 'Previous']();
      this[(limitRight ? 'hide' : 'show') + 'Next']();

      this.setPreviousEvent(function(){
         this.renderDays(date.decrement('month', months), 'left');
      }.bind(this));

      this.setNextEvent(function(){
         this.renderDays(date.increment('month', months), 'right');
      }.bind(this));

      var canGoUp = options.pickOnly != 'days' || options.canAlwaysGoUp.contains('days');
      var titleEvent = (canGoUp) ? function(){
         this.renderMonths(date, 'fade');
      }.bind(this) : null;
      this.setTitleEvent(titleEvent);

      this.currentView = 'days';
   },

   renderTime: function(date, fx){
      var options = this.options;
      this.setTitle(date, options.time_title);

      var originalColumns = this.originalColumns = options.columns;
      this.currentView = null; // otherwise you'd get crazy recursion
      if (originalColumns != 1) this.setColumns(1);

      this.setContent(renderers.time(
         options,
         date.clone(),
         function(date){
            this.select(date);
         }.bind(this)
      ), fx);

      // Hide « and » buttons
      this.hidePrevious()
         .hideNext()
         .setPreviousEvent(null)
         .setNextEvent(null);

      var canGoUp = options.pickOnly != 'time' || options.canAlwaysGoUp.contains('time');
      var titleEvent = (canGoUp) ? function(){
         this.setColumns(originalColumns, 'days', date, 'fade');
      }.bind(this) : null;
      this.setTitleEvent(titleEvent);

      this.currentView = 'time';
   },

   select: function(date, all){
      this.date = date;
      var formatted = date.format(this.options.format),
         time = date.strftime(),
         inputs = (!this.options.updateAll && !all && this.input) ? [this.input] : this.inputs;

      inputs.each(function(input){
         input.set('value', formatted).store('datepicker:value', time).fireEvent('change');
      }, this);

      this.fireEvent('select', [date].concat(inputs));
      this.close();
      return this;
   }

});

// Renderers only output elements and calculate the limits!
var timesSelectors = {
   years: function(options, date){
      var times = [];
      for (var i = 0; i < options.yearsPerPage; i++){
         times.push(+date);
         date.increment('year', 1);
      }
      return times;
   },

   months: function(options, date){
      var times = [];
      date.set('month', 0);
      for (var i = 0; i <= 11; i++){
         times.push(+date);
         date.increment('month', 1);
      }
      return times;
   },

   days: function(options, date){
      var times = [];
      date.set('date', 1);
      while (date.get('day') != options.startDay) date.set('date', date.get('date') - 1);
      for (var i = 0; i < 42; i++){
         times.push(+date);
         date.increment('day',  1);
      }
      return times;
   }

};

var renderers = {
   years: function(years, options, currentDate, dateElements, fn){
      var container = new Element('table.years'),
         today     = new Date(),
         rows      = [],
         element, classes;

      years.each(function(_year, i){
         var date = new Date(_year), year = date.get('year');
         if (i % 4 === 0) {
            rows.push(new Element('tr'));
            rows[rows.length - 1].inject(container)
         }
         classes = '.year.year' + i;
         if (year == today.get('year')) classes += '.today';
         if (year == currentDate.get('year')) classes += '.selected';
         element = new Element('td' + classes, {text: year}).inject(rows[rows.length - 1]);

         dateElements.push({element: element, time: _year});

         if (isUnavailable('year', date, options)) element.addClass('unavailable');
         else element.addEvent('click', fn.pass(date));
      });

      return container;
   },

   months: function(months, options, currentDate, dateElements, fn){
      var today        = new Date(),
         month        = today.get('month'),
         thisyear     = today.get('year'),
         selectedyear = currentDate.get('year'),
         container    = new Element('table.months'),
         monthsAbbr   = options.months_abbr || Locale.get('Date.months_abbr'),
         rows         = [],
         element, classes;

      months.each(function(_month, i){
         var date = new Date(_month), year = date.get('year');
         if (i % 3 === 0) {
            rows.push(new Element('tr'));
            rows[rows.length - 1].inject(container)
         }

         classes = '.month.month' + (i + 1);
         if (i == month && year == thisyear) classes += '.today';
         if (i == currentDate.get('month') && year == selectedyear) classes += '.selected';
         element = new Element('td' + classes, {text: monthsAbbr[i]}).inject(rows[rows.length - 1]);
         dateElements.push({element: element, time: _month});

         if (isUnavailable('month', date, options)) element.addClass('unavailable');
         else element.addEvent('click', fn.pass(date));
      });

      return container;
   },

   days: function(days, options, currentDate, dateElements, fn){
      var month = new Date(days[14]).get('month'),
         todayString = new Date().toDateString(),
         currentString = currentDate.toDateString(),
         weeknumbers = options.weeknumbers,
         container = new Element('table.days' + (weeknumbers ? '.weeknumbers' : ''), {
            role: 'grid', 'aria-labelledby': this.titleID
         }),
         header = new Element('thead').inject(container),
         body = new Element('tbody').inject(container),
         titles = new Element('tr.titles').inject(header),
         localeDaysShort = options.days_abbr || Locale.get('Date.days_abbr'),
         day, classes, element, weekcontainer, dateString,
         where = options.rtl ? 'top' : 'bottom';

      if (weeknumbers) new Element('th.title.day.weeknumber', {
         text: Locale.get('DatePicker.week')
      }).inject(titles);

      for (day = options.startDay; day < (options.startDay + 7); day++){
         new Element('th.title.day.day' + (day % 7), {
            text: localeDaysShort[(day % 7)],
            role: 'columnheader'
         }).inject(titles, where);
      }

      days.each(function(_date, i){
         var date = new Date(_date);

         if (i % 7 == 0){
            weekcontainer = new Element('tr.week.week' + (Math.floor(i / 7))).set('role', 'row').inject(body);
            if (weeknumbers) new Element('th.day.weeknumber', {text: date.get('week'), scope: 'row', role: 'rowheader'}).inject(weekcontainer);
         }

         dateString = date.toDateString();
         classes = '.day.day' + date.get('day');
         if (dateString == todayString) classes += '.today';
         if (date.get('month') != month) classes += '.otherMonth';
         element = new Element('td' + classes, {text: date.getDate(), role: 'gridcell'}).inject(weekcontainer, where);

         if (dateString == currentString) element.addClass('selected').set('aria-selected', 'true');
         else element.set('aria-selected', 'false');

         dateElements.push({element: element, time: _date});

         if (isUnavailable('date', date, options)) element.addClass('unavailable');
         else element.addEvent('click', fn.pass(date.clone()));
      });

      return container;
   },

   time: function(options, date, fn){
      var container = new Element('div.time'),
         // make sure that the minutes are timeWheelStep * k
         initMinutes = (date.get('minutes') / options.timeWheelStep).round() * options.timeWheelStep

      if (initMinutes >= 60) initMinutes = 0;
      date.set('minutes', initMinutes);

      var hoursInput = new Element('input.hour[type=text]', {
         title: Locale.get('DatePicker.use_mouse_wheel'),
         value: date.format('%H'),
         events: {
            click: function(event){
               event.target.focus();
               event.stop();
            },
            mousewheel: function(event){
               event.stop();
               hoursInput.focus();
               var value = hoursInput.get('value').toInt();
               value = (event.wheel > 0) ? ((value < 23) ? value + 1 : 0)
                  : ((value > 0) ? value - 1 : 23)
               date.set('hours', value);
               hoursInput.set('value', date.format('%H'));
            }.bind(this)
         },
         maxlength: 2
      }).inject(container);

      new Element('div.separator[text=:]').inject(container);

      var minutesInput = new Element('input.minutes[type=text]', {
         title: Locale.get('DatePicker.use_mouse_wheel'),
         value: date.format('%M'),
         events: {
            click: function(event){
               event.target.focus();
               event.stop();
            },
            mousewheel: function(event){
               event.stop();
               minutesInput.focus();
               var value = minutesInput.get('value').toInt();
               value = (event.wheel > 0) ? ((value < 59) ? (value + options.timeWheelStep) : 0)
                  : ((value > 0) ? (value - options.timeWheelStep) : (60 - options.timeWheelStep));
               if (value >= 60) value = 0;
               date.set('minutes', value);
               minutesInput.set('value', date.format('%M'));
            }.bind(this)
         },
         maxlength: 2
      }).inject(container);


      new Element('input.ok', {
         'type': 'submit',
         value: Locale.get('DatePicker.time_confirm_button'),
         events: {click: function(event){
            event.stop();
            date.set({
               hours: hoursInput.get('value').toInt(),
               minutes: minutesInput.get('value').toInt()
            });
            fn(date.clone());
         }}
      }).inject(container);

      return container;
   }

};

Picker.Date.defineRenderer = function(name, fn){
   renderers[name] = fn;
   return this;
};

Picker.Date.getRenderer = function(name) {
   return renderers[name];
}

var limitDate = function(date, min, max){
   if (min && date < min) return min;
   if (max && date > max) return max;
   return date;
};

var isUnavailable = function(type, date, options){
   var minDate = options.minDate,
      maxDate = options.maxDate,
      availableDates = options.availableDates,
      year, month, day, ms;

   if (!minDate && !maxDate && !availableDates) return false;
   date.clearTime();

   if (type == 'year'){
      year = date.get('year');
      return (
         (minDate && year < minDate.get('year')) ||
         (maxDate && year > maxDate.get('year')) ||
         (
            (availableDates != null &&  !options.invertAvailable) && (
               availableDates[year] == null ||
               Object.getLength(availableDates[year]) == 0 ||
               Object.getLength(
                  Object.filter(availableDates[year], function(days){
                     return (days.length > 0);
                  })
               ) == 0
            )
         )
      );
   }

   if (type == 'month'){
      year = date.get('year');
      month = date.get('month') + 1;
      ms = date.format('%Y%m').toInt();
      return (
         (minDate && ms < minDate.format('%Y%m').toInt()) ||
         (maxDate && ms > maxDate.format('%Y%m').toInt()) ||
         (
            (availableDates != null && !options.invertAvailable) && (
               availableDates[year] == null ||
               availableDates[year][month] == null ||
               availableDates[year][month].length == 0
            )
         )
      );
   }

   // type == 'date'
   year = date.get('year');
   month = date.get('month') + 1;
   day = date.get('date');

   var dateAllow = (minDate && date < minDate) || (maxDate && date > maxDate);
   if (availableDates != null){
      dateAllow = dateAllow
         || availableDates[year] == null
         || availableDates[year][month] == null
         || !availableDates[year][month].contains(day);
      if (options.invertAvailable) dateAllow = !dateAllow;
   }

   return dateAllow;
};
} )();

var Pickers = new Class( {
   Implements: [ Options ],

   options       : {
      pickerClass: 'datepicker_vista',
      selector   : [ '.pick-date', '.pick-datetime', '.pick-time' ]
   },

   initialize: function( options ) {
      this.aroundSetOptions( options ); this.build();
   },

   build: function() {
      this.options.selector.each( function( selector ) {
         $$( selector ).each( function( el ) {
            if (! el.id) el.id = String.uniqueID();

            if (! this.collection.contains( el.id )) {
               var opts = { pickerClass: this.options.pickerClass };

               if (el.hasClass( 'clearable' )) { opts.blockKeydown = false }

               if (el.hasClass( 'pick-date')) {
                  opts[ 'format' ] = '%d/%m/%Y';
               }

               if (el.hasClass( 'pick-datetime')) {
                  opts[ 'format' ] = '%d/%m/%Y @ %H:%M';
                  opts[ 'timePicker' ] = true;
                  opts[ 'timeWheelStep' ] = 5;
               }

               if (el.hasClass( 'pick-time')) {
                  opts[ 'format'        ] = '%H:%M';
                  opts[ 'pickOnly'      ] = 'time';
                  opts[ 'timeWheelStep' ] = 5;
               }

               new Picker.Date( el.id, opts );
               this.collection.include( el.id );
            }
         }, this );
      }, this );
   }
} );

var Replacements = new Class( {
   Implements: [ Options ],

   options              : {
      replacement_class : 'checkbox',
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
         var span  = new Element( 'span', {
            'class': opt.replacement_class + (el.checked ? ' checked' : ''),
            id     : new_id,
            name   : el.name
         } ).inject( el, 'before' );
         return span;
      }

      if (el.type == 'textarea' || el.type == 'text') {
         var div  = new Element( 'div',  { 'class': opt.textarea_container } );
         var pre  = new Element( 'pre',  { 'class': opt.textarea_preformat } );
         var span = new Element( 'span', { id: new_id } );

         div.inject( el, 'before' ); pre.inject( div ); div.grab( el );
         span.inject( pre ); new Element( 'br' ).inject( pre );
         span.set( 'text', el.value );
         return span;
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
      methods = Array.convert( methods );

      Array.convert( events ).each( function( event, index ) {
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

      if (!replacement) return; replacement.toggleClass( 'checked' );

      if (replacement.hasClass( 'checked' )) {
         el.setProperty( 'checked', 'checked' ); el.fireEvent( 'checked' );

         if (el.type == 'radio') {
            this.collection.each( function( box_id ) {
               var box = $( box_id ), replacement = $( box_id + opt.suffix );

               if (replacement && box_id != el.id && box.name == el.name
                   && replacement.hasClass( 'checked' )) {
                  replacement.removeClass ( 'checked' );
                  box.removeProperty( 'checked' );
                  box.fireEvent( 'checked' );
               }
            }, this );
         }
      }
      else { el.removeProperty( 'checked' ); el.fireEvent( 'checked' ); }
   }
} );

var ServerUtils = new Class( {
   Implements: [ Options, LoadMore ],

   options: { config_attr: 'server', selector: '.server', url: null },

   initialize: function( options ) {
      this.aroundSetOptions( options ); this.build();
   },

   asyncTips: function( action, id, val ) {
      this.request( action, id, val, function () { $( id ).show() } );
   },

   checkField: function( id, form, domain ) {
      var action = 'check-field';

      if (form && domain) action += '?domain=' + domain + '&form=' + form;

      this.request( action, id, $( id ).value, function( resp ) {
         $( resp.id ).className = resp.class_name ? resp.class_name : 'hidden';
      }.bind( this ) );
   },

   requestIfVisible: function( action, id, val, on_complete ) {
      if ($( id ).isVisible()) this.request( action, id, val, on_complete );
   },

   showIfNeeded: function( action, id, target ) {
      this.request( action, id, $( id ).value, function( resp ) {
         if (resp.needed) { $( target ).show( resp.display ) }
         else { $( target ).hide() }
      }.bind( this ) );
   }
} );

var Sliders = new Class( {
   Implements: [ Options ],

   options: { config_attr: 'slider', selector: '.slider' },

   initialize: function( options ) {
      this.aroundSetOptions( options ); this.build();
   },

   attach: function( el ) {
      var cfg, slider, submit = this.context.submit;

      if (! (cfg = this.config[ el.id ])) return;

      var form_name = cfg.form_name; delete cfg[ 'form_name' ];
      var name      = cfg.name;      delete cfg[ 'name'      ];
      var default_v = cfg.value;     delete cfg[ 'value'     ];
      var knob      = el.getElement( 'span' );

      cfg = Object.append( cfg, {
         onChange: function( value ) {
            submit.setField.call( submit, name, value, form_name ) }
      } );

      new Slider( el, knob, cfg ).set( default_v );
   }
} );

var SubmitUtils = new Class( {
   Implements: [ Options ],

   options       : {
      config_attr: 'submit',
      formName   : null,
      selector   : '.submit',
      target     : null,
      wildCards  : [ '%', '*' ]
   },

   initialize: function( options ) {
      this.aroundSetOptions( options );
      this.form = document.forms ? document.forms[ this.options.formName ]
                                 : function() {};

      if (this.options.target == 'top') this.placeOnTop();

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

   location: function( href ) {
      window.location = href;
   },

   placeOnTop: function() {
      if (self != top) {
         if (document.images) top.location.replace( window.location.href );
         else top.location.href = window.location.href;
      }
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

   setField: function( name, value, form_name ) {
      var form = form_name ? document.forms[ form_name ] : this.form;
      var el; if (name && (el = form.elements[ name ])) el.value = value;

      return el ? el.value : null;
   },

   submitForm: function( button_value, form_name ) {
      var form;

      if (form_name) { form = document.forms[ form_name ] }
      else { form = this.form }

      if (!button_value) { form.submit(); return true; }

      var button; $$( '*[name=_method]' ).some( function( el ) {
         if (el.value == button_value) { button = el; return true }
         return false;
      }.bind( this ) );

      if (button) { this.detach( button ); button.click() }
      else {
         new Element( 'input', {
            name: '_method', type: 'hidden', value: button_value
         } ).inject( $( form ) );
      }

      form.submit();
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
         'class' : klass + '-term', 'id' : klass + '-term' } ).inject( dlist );
      this.defn = new Element( 'dd', {
         'class' : klass + '-defn', 'id' : klass + '-defn' } ).inject( dlist );
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

   options: { config_attr: 'togglers', selector: '.togglers' },

   initialize: function( options ) {
      this.aroundSetOptions( options ); this.build();

      this.resize = this.context.resize.bind( this.context );
   },

   attach: function( el ) {
      var cfg; if (! (cfg = this.config[ el.id ])) return;

      el.addEvent( cfg.event || 'click', function( ev ) {
         this[ cfg.method ].apply( this, cfg.args ) }.bind( this ) );
   },

   hide: function( target_id ) {
      var target = $( target_id ); if (!target) return;

      target.hide();
   },

   showSelected: function( src_id, sink_id ) {
      var src = $( src_id ), target = $( sink_id );

      if (! src || ! target) return;

      if (src.getProperty( 'checked' )) { target.show() }
      else { target.hide() }
   },

   toggleSwapText: function( id, name, s1, s2 ) {
      var cookies = this.context.cookies, el; if (! name) return;

      if (cookies.get( name ) == 'true') {
         cookies.set( name, 'false' );

         if (el = $( id )) el.set( 'html', s2 );
         if (el = $( name + 'Disp' )) el.hide();
      }
      else {
         cookies.set( name, 'true' );

         if (el = $( id )) el.set( 'html', s1 );
         if (el = $( name + 'Disp' )) el.show();
      }

      this.resize();
   }
} );

var WindowUtils = new Class( {
   Implements: [ Options, LoadMore ],

   options       : {
      config_attr: 'window',
      customLogFn: false,
      height     : 600,
      maskOpts   : {},
      quiet      : false,
      selector   : '.windows',
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

      if (typeof console == "undefined") {
         console[ 'log'  ] = function( msg ) { window.alert( msg ); };
         console[ 'warn' ] = function( msg ) { window.alert( msg ); };
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

      this.dialogs = [];
      this.build();
   },

   inlineDialog: function( href, options ) {
      var opt = this.mergeOptions( options ), id = opt.name + '_dialog', dialog;

      if (! (dialog = this.dialogs[ opt.name ])) {
         var content = new Element( 'div', {
            'id': id } ).appendText( 'Loading...' );
         var el      = $( opt.target );

         opt.maskOpts.id     = 'mask-' + opt.name;
         opt.maskOpts.inject = { 'target': null, 'where': 'inside' };
         dialog = this.dialogs[ opt.name ] = new Dialog( el, content, opt );
      }

      this.request( href, id, opt.value || '', opt.onComplete || function() {
         this.rebuild(); dialog.show() } );

      return dialog;
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

   showIfNeeded: function( id, value, target, display ) {
      display = display || 'inline-block';

      if ($( id ).value == value) { $( target ).show( display ) }
      else { $( target ).hide() }
   }
} );
