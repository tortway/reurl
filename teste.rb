source<<%Q|
        if(m != ''){
          if(typeof(Storage) !== "undefined") {
            if(localStorage.getItem('qwe#{time_is}')){
              m='';
              target='#{alt_target}';
            }
          }else {
            //пока без альтернатив
          }
          alert(1)
          var mySwfStore = new SwfStore({
            namespace: 'reurl',
            swf_url: 'http://reurl.ru:4567/js/reurl.swf',
            debug: true,
            onready: function(){
              alert(2)
              if(mySwfStore.get('qwe#{time_is}')=='1'){
                alert(3)
                m='';
                target='#{alt_target}';
              }
              alert('4: '+mySwfStore.get('qwe#{time_is}')+' qwe#{time_is}')
            },
            onerror: function(){
              alert(5)
              //qwe
            }
          });
          alert(6)
        }
      |

source=%Q|
          localStorage.setItem('qweasd#{time_is}', '1');
          var mySwfStore = new SwfStore({
            namespace: 'reurl',
            swf_url: 'http://reurl.ru:4567/js/reurl.swf',
            debug: true,
            onready: function(){
              mySwfStore.set('qwe#{time_is}', '1');
              alert('qwe#{time_is} is saved!')
            },
            onerror: function(){
              //qwe
            }
          });
        |