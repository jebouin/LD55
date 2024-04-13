package entities;

class Item extends Entity {
    public var id : String;
    var item : Data.Item = null;

    public function new(id:String, roomId:String, tx:Int, ty:Int) {
        super(id, roomId, tx, ty);
        isGround = true;
        item = Data.item.resolve(id);
        this.id = id;
    }

    override public function onSteppedOnBy(e:Summon) {
        if(item.hpAdd > 0) {
            Game.inst.hero.hp += item.hpAdd;
        }
        if(item.mpAdd > 0) {
            Game.inst.hero.mp += item.mpAdd;
        }
        if(id == "key1") {
            Game.inst.inventory.gainKey(1);
        } else if(id == "key2") {
            Game.inst.inventory.gainKey(2);
        } else if(id == "key3") {
            Game.inst.inventory.gainKey(3);
        } else if(id == "scrollSlime") {
            Game.inst.inventory.addSpell(slime);
        } else if(id == "scrollGnome") {
            Game.inst.inventory.addSpell(gnome);
        } else if(id == "scrollDragon") {
            Game.inst.inventory.addSpell(dragon);
        }
        delete();
        Game.inst.onChange();
    }
}