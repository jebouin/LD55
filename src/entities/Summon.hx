package entities;

import format.as1.Data.PushItem;

enum Step {
    Move(dx:Int, dy:Int);
    TryMove(dx:Int, dy:Int);
    Hit(target:Enemy);
    Open(door:Door);
}

class Summon extends Entity {
    public static inline var SOD_F = 4.583;
    public static inline var SOD_Z = .559;
    public static inline var SOD_R = -1.016;
    public static inline var STEP_DURATION = 2. / 60;
    @:s var kind : Data.SummonKind;
    var summon : Data.Summon;
    @:s var facingX : Int = 0;
    @:s var facingY : Int = 1;
    public var controlled(default, set) : Bool = false;
    public var ignoreSlippery(get, never) : Bool;
    var queue : Array<Step> = [];
    public var canTakeAction : Bool = true;
    var queueTimer : EaseTimer;
    @:s var sodX : SecondOrderDynamics;
    @:s var sodY : SecondOrderDynamics;

    public function new(kind:Data.SummonKind, roomId:String, tx:Int, ty:Int, initial:Bool) {
        this.kind = kind;
        summon = Data.summon.get(kind);
        this.tx = tx;
        this.ty = ty;
        sodX = new SecondOrderDynamics(SOD_F, SOD_Z, SOD_R, getDisplayX(), Precise);
        sodY = new SecondOrderDynamics(SOD_F, SOD_Z, SOD_R, getDisplayY(), Precise);
        super("", roomId, tx, ty, summon.hp, summon.atk, summon.def);
        mp = summon.mp;
        if(!initial) {
            onMoved();
        }
        Game.inst.setHero(this);
    }

    override public function init(?animName:String=null) {
        super.init(getAnimName());
        queueTimer = new EaseTimer(STEP_DURATION);
        targetable = true;
        friendly = true;
    }

    public function tryMove(dx:Int, dy:Int) {
        var level = Game.inst.level;
        var moving = true, moved = false, attacked = false, opened = false;
        var ctx = tx, cty = ty;
        while(moving) {
            var nx = ctx + dx;
            var ny = cty + dy;
            if(!level.collides(nx, ny)) {
                pushStep(Move(dx, dy));
                ctx = nx;
                cty = ny;
                moved = true;
                if(!level.isSlippery(ctx, cty) || kind == slime) {
                    moving = false;
                }
            } else {
                for(e in Game.inst.entities) {
                    if(!e.collides(nx, ny)) continue;
                    if(Std.isOfType(e, Enemy)) {
                        var enemy = cast(e, Enemy);
                        pushStep(Hit(enemy));
                        attacked = true;
                        break;
                    }
                    if(Std.isOfType(e, Door)) {
                        var door = cast(e, Door);
                        pushStep(Open(door));
                        opened = true;
                        break;
                    }
                }
                break;
            }
        }
        return moved || opened || attacked;
    }

    function onMoved() {
        for(e in Game.inst.entities) {
            if(!e.deleted && e.isGround && e.tx == tx && e.ty == ty && e.active) {
                e.onSteppedOnBy(this);
                break;
            }
        }
        Game.inst.onChange();
        if(kind == slime) {
            Game.inst.level.addSlime(tx, ty);
        }
    }

    public function setFacing(dx:Int, dy:Int) {
        if(facingX == dx && facingY == dy) return;
        facingX = dx;
        facingY = dy;
        updateAnim();
        Game.inst.onChange();
    }

    inline function getAnimName() {
        var base = kind.toString();
        var dirStr = "";
        if(facingX == 0 && facingY == 1) {
            dirStr = "Down";
        }
        if(facingX == 0 && facingY == -1) {
            dirStr = "Up";
        }
        if(facingX == 1 && facingY == 0) {
            dirStr = "Right";
        }
        if(facingX == -1 && facingY == 0) {
            dirStr = "Left";
        }
        return base + dirStr;
    }

    public override function update(dt:Float) {
        super.update(dt);
        if(!canTakeAction) {
            queueTimer.update(dt);
            if(queueTimer.isDone()) {
                popStep();
                queueTimer.restart();
            }
        }
        sodX.update(dt, getDisplayX());
        sodY.update(dt, getDisplayY());
    }

    function updateAnim() {
        anim.playFromName("entities", getAnimName());
    }
    override function updateVisual() {
        anim.x = sodX.pos;
        anim.y = sodY.pos;
    }

    public function castSpell(id:Data.SpellKind) {
        var def = Data.spell.get(id);
        if(mp < def.cost) return false;
        var entityFront = Game.inst.getEntity(tx + facingX, ty + facingY);
        var collidesFront = Game.inst.level.collides(tx + facingX, ty + facingY);
        if(collidesFront) return false;
        switch(id) {
            case kick:
                if(entityFront == null || entityFront.isGround) return false;
                hit(entityFront);
            case slime:
                if(entityFront != null) return false;
                new Summon(Data.SummonKind.slime, roomId, tx + facingX, ty + facingY, false);
            case gnome:
                if(entityFront != null) return false;
                new Summon(Data.SummonKind.gnome, roomId, tx + facingX, ty + facingY, false);
            case dragon:
                if(entityFront != null) return false;
                new Summon(Data.SummonKind.dragon, roomId, tx + facingX, ty + facingY, false);
        }
        Game.inst.level.updateActive();
        mp -= def.cost;
        Game.inst.onChange();
        return true;
    }

    public function canCastSpell(id:Data.SpellKind) {
        var def = Data.spell.get(id);
        var entityFront = Game.inst.getEntity(tx + facingX, ty + facingY);
        var collidesFront = Game.inst.level.collides(tx + facingX, ty + facingY);
        if(collidesFront) return false;
        switch(id) {
            case kick:
                return true;
            case slime:
                if(entityFront != null) return false;
            case gnome:
                if(entityFront != null) return false;
            case dragon:
                if(entityFront != null) return false;
        }
        return mp >= def.cost;
    }

    public function set_controlled(v:Bool) {
        this.controlled = v;
        return v;
    }

    public function pushStep(step:Step) {
        if(queue.length == 0) {
            queueTimer.t = 1;
        }
        queue.push(step);
        canTakeAction = false;
    }
    function popStep() {
        var step = queue.shift();
        trace("popStep", step);
        switch(step) {
            case Move(dx, dy):
                tx += dx;
                ty += dy;
                setFacing(dx, dy);
                onMoved();
            case TryMove(dx, dy):
                tryMove(dx, dy);
            case Hit(target):
                hit(target);
                if(!target.deleted) {
                    target.hit(this);
                }
            case Open(door):
                if(Game.inst.inventory.spendKey(door.type)) {
                    door.open();
                }
        }
        updateVisual();
        Game.inst.onChange();
        if(queue.length == 0) {
            canTakeAction = true;
            return;
        }
    }

    public function get_ignoreSlippery() {
        return kind == slime;
    }
}