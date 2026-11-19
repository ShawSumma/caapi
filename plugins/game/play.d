module plugins.game.play;

import plugins.api.content : Content;

enum string BROKE = "broke";
enum string PLACED = "placed";
enum string CRAFTED = "crafted";
enum string WOKE = "woke";

struct Play {
    void* host;
    const(Content)* content;
    void function(const(Play)* play, const(char)[] item, uint count) give;
    void function(const(Play)* play, const(char)[] insight) learn;
    void function(const(Play)* play, const(char)[] text) note;
}
