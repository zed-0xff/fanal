var ZHexDump = {
  data: null,
  width: 0x10,
  last_target: null,

  increase_width: function(){
    this.width++;
    this.dump();
  },

  decrease_width: function(){
    if(this.width>1){
      this.width--;
      this.dump();
    }
  },

  dump: function(){
    this.dump_to(this.last_target);
  },

  fmt_addr: function(offset){
    addr = (offset+this.offset).toString(16);
    switch(addr.length){ // trying to optimize for speed
      case 0: addr="00000000"+addr; break;
      case 1: addr="0000000"+addr; break;
      case 2: addr="000000"+addr; break;
      case 3: addr="00000"+addr; break;
      case 4: addr="0000"+addr; break;
      case 5: addr="000"+addr; break;
      case 6: addr="00"+addr; break;
      case 7: addr="0"+addr; break;
    }
    return addr;
  },

  dump_to: function(target_el){
    var r = '';
    var data = this.data;
    var offset,j,c,addr;
    var width = this.width;
    var ascii = "";
    var hexline, hexline0 = "";

    this.last_target = target_el;

    for(offset=0; offset<data.length; offset+=width){
      addr = (offset+this.offset).toString(16);
      switch(addr.length){ // trying to optimize for speed
        case 0: addr="00000000"+addr; break;
        case 1: addr="0000000"+addr; break;
        case 2: addr="000000"+addr; break;
        case 3: addr="00000"+addr; break;
        case 4: addr="0000"+addr; break;
        case 5: addr="000"+addr; break;
        case 6: addr="00"+addr; break;
        case 7: addr="0"+addr; break;
      }

      c = data.charCodeAt(offset) & 0xff;
      hexline = (c<0x10 ? '0' : '') + c.toString(16) + " ";
      ascii = (c>0x1f && c<0x7f) ? data[offset] : ".";

      for(j=1;j<width;j++){
        if(j%8 == 0) hexline += ' ';
        c = data.charCodeAt(offset+j);
        if(isNaN(c)){
          hexline += '   '; ascii += ' ';
        } else {
          c &= 0xff;
          hexline += (c<0x10 ? '0' : '') + c.toString(16) + " ";
          ascii += (c>0x1f && c<0x7f) ? data[offset+j] : ".";
        }
      }
      if( hexline == hexline0 ){
        if(r.charAt(r.length-2) != '*') r += "*\n";
      } else {
        r += this.fmt_addr(offset) + ":  " + hexline + " |" + ascii + "|\n";
      }
      hexline0 = hexline;
    }

    if(r.substr(-2) == "*\n") r += this.fmt_addr(offset) + ":";

    $(target_el).text(r);
  },

  // AJAXy part
  offset: 0,
  size: 0,
  pagesize: 0x20000,

  load: function(offset,size){
    this.offset = isNaN(offset) ? this.offset : offset;
    this.size = isNaN(size) ? this.size : size;
    $.get("hexdump?raw=1&offset="+this.offset+"&size="+this.size,
      function(data){
        ZHexDump.data = data;
        ZHexDump.dump_to("pre#hexdump_data");
        ZHexDump.update_labels();
      }
    );
  },

  update_labels: function(){
    $('#hexdump .info .offset'    ).text(this.offset);
    $('#hexdump .info .offset_hex').text(this.offset.toString(16));
    $('#hexdump .info .size'      ).text(this.data.length);
    $('#hexdump .info .size_hex'  ).text(this.data.length.toString(16));
  }
};
