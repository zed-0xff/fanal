var ZHexDump = {
  data: "foo",
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
 
  dump_to: function(target_el){
    var r = '';
    var data = this.data;
    var offset,j,c,s;
    var width = this.width;
    var ascii = "";

    this.last_target = target_el;

    for(offset=0; offset<data.length; offset+=width){
      s = offset.toString(16);
      switch(s.length){ // trying to optimize for speed
        case 0: s="00000000"+s; break;
        case 1: s="0000000"+s; break;
        case 2: s="000000"+s; break;
        case 3: s="00000"+s; break;
        case 4: s="0000"+s; break;
        case 5: s="000"+s; break;
        case 6: s="00"+s; break;
        case 7: s="0"+s; break;
      }
      r += s + ":  ";

      c = data.charCodeAt(offset) & 0xff;
      r += (c<0x10 ? '0' : '') + c.toString(16) + " ";
      ascii = (c>0x1f && c<0x7f) ? data[offset] : ".";

      for(j=1;j<width;j++){
        if(j%8 == 0) r+=' ';
        c = data.charCodeAt(offset+j) & 0xff;
        r += (c<0x10 ? '0' : '') + c.toString(16) + " ";
        ascii += (c>0x1f && c<0x7f) ? data[offset+j] : ".";
      }
      r += " |" + ascii + "|\n";
    }

    $(target_el).text(r);
  },
};
