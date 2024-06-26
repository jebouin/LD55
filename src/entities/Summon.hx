package entities;

import audio.Audio;
import format.as1.Data.PushItem;

enum Step {
    Move(dx:Int, dy:Int);
    TryMove(dx:Int, dy:Int, careful:Bool);
    Hit(target:Enemy);
    HitSummon(target:Summon);
    TakeHit(source:Entity);
    Open(door:Door);
}

class Summon extends Entity {
    public static inline var PERK_MULT_HP = 20;
    public static inline var PERK_MULT_ATK = 1;
    public static inline var STEP_DURATION_WALK = 2. / 60;
    public static inline var STEP_DURATION_HIT = 5. / 60;
    public static inline var STEP_DURATION_HIT_SUMMON = 3. / 60;
    @:s public var kind : Data.SummonKind;
    public var summon : Data.Summon;
    @:s var facingX : Int = 0;
    @:s var facingY : Int = 1;
    public var controlled(default, set) : Bool = false;
    public var ignoreSlippery(get, never) : Bool;
    var queue : Array<Step> = [];
    public var canTakeAction : Bool = true;
    var queueTimer : EaseTimer;

    @:s public var spells : Array<Data.SpellKind> = [];
    @:s public var spellUsedCount : Array<Int> = [];
    @:s public var xp : Int = 0;
    @:s public var level : Int = 1;
    @:s public var levelsPending : Int = 0;
    @:s public var totalXP : Int = 0;
    public var xpPending(get, never) : Int;
    public var xpPendingSOD : SecondOrderDynamics;

    public function new(kind:Data.SummonKind, floorId:Int, tx:Int, ty:Int, initial:Bool) {
        this.kind = kind;
        summon = Data.summon.get(kind);
        super("", floorId, tx, ty, summon.hp, summon.atk, summon.def);
        mp = summon.mp;
        if(!initial) {
            onMoved();
        }
        Game.inst.setHero(this);
        spells = [kick];
        spellUsedCount = [0];
        if(kind == slime) {
            spells.push(sleep);
            spellUsedCount.push(0);
        } else if(kind == gnome) {
            spells.push(levelUp);
            spellUsedCount.push(0);
        } else if(kind == dragon) {
            spells.push(fireBreath);
            spellUsedCount.push(0);
        }
    }

    override public function init(?animName:String=null) {
        summon = Data.summon.get(kind);
        super.init(getAnimName());
        queueTimer = new EaseTimer(STEP_DURATION_WALK);
        targetable = true;
        friendly = true;
        xpPendingSOD = new SecondOrderDynamics(1, 1, 1, xpPending, Precise);
        updateAnim();
    }

    public function tryMove(dx:Int, dy:Int, careful:Bool) {
        var entityFront = Game.inst.getEntity(tx + dx, ty + dy);
        if(entityFront != null && (Std.isOfType(entityFront, Enemy) || Std.isOfType(entityFront, Summon))) {
            if(Game.FORCE_FACING && (facingX != dx || facingY != dy)) {
                setFacing(dx, dy);
                return false;
            }
        }
        setFacing(dx, dy);
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
                    if((!moved || Game.SLIDE_ATTACK) && Std.isOfType(e, Enemy) && !careful) {
                        var enemy = cast(e, Enemy);
                        pushStep(Hit(enemy));
                        if(!wouldKill(enemy)) {
                            pushStep(TakeHit(enemy));
                        }
                        attacked = true;
                        break;
                    }
                    if((!moved || Game.SLIDE_ATTACK) && Std.isOfType(e, Summon) && !careful) {
                        var summon = cast(e, Summon);
                        pushStep(HitSummon(summon));
                        attacked = true;
                        break;
                    }
                    if(!moved && Std.isOfType(e, Door)) {
                        var door = cast(e, Door);
                        if(door.canOpen()) {
                            pushStep(Open(door));
                            opened = true;
                        }
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

    function getAnimName() {
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
        if(!controlled) {
            dirStr += "Sleep";
        }
        return base + dirStr;
    }

    public override function update(dt:Float) {
        super.update(dt);
        if(!canTakeAction) {
            queueTimer.update(dt);
            if(queueTimer.isDone()) {
                var delay = popStep();
                queueTimer.restartAt(delay);
            }
        }
        xpPendingSOD.update(dt, xpPending);
    }

    function updateAnim() {
        anim.playFromName("entities", getAnimName());
    }
    override function updateVisual() {
        anim.x = sodX.pos;
        anim.y = sodY.pos;
    }

    public function getSpellCost(i:Int) {
        var mult = Math.pow(2, spellUsedCount[i]);
        return Math.floor(Data.spell.get(spells[i]).cost * mult);
    }

    public function castSpell(id:Data.SpellKind) {
        var pos = spells.indexOf(id);
        var cost = getSpellCost(pos);
        if(mp < cost) return false;
        var entityFront = getEntityFront();
        var collidesFront = Game.inst.level.collides(tx + facingX, ty + facingY, false);
        if(collidesFront) return false;
        switch(id) {
            case kick:
                if(entityFront == null) {
                    Game.inst.fx.hitAnim(Level.TS * (tx + facingX + .5), Level.TS * (ty + facingY + .5), facingX, facingY);
                }
                if(entityFront == null || entityFront.isGround) return false;
                tryMove(facingX, facingY, false);
            case slime:
                if(entityFront != null) return false;
                new Summon(Data.SummonKind.slime, floorId, tx + facingX, ty + facingY, false);
            case gnome:
                if(entityFront != null) return false;
                new Summon(Data.SummonKind.gnome, floorId, tx + facingX, ty + facingY, false);
            case dragon:
                if(entityFront != null) return false;
                new Summon(Data.SummonKind.dragon, floorId, tx + facingX, ty + facingY, false);
            case sleep:
                hp += 20;
            case levelUp:
                giveXP(getXPNeeded());
            case fireBreath:
                if(entityFront == null || entityFront.isGround) return false;
                entityFront.atk >>= 1;
        }
        Game.inst.level.updateActive();
        mp -= cost;
        spellUsedCount[pos]++;
        Game.inst.onChange();
        return true;
    }
    public function canCastSpell(id:Data.SpellKind) {
        var pos = spells.indexOf(id);
        var cost = getSpellCost(pos);
        if(mp < cost) return false;
        var entityFront = Game.inst.getEntity(tx + facingX, ty + facingY);
        var collidesFront = Game.inst.level.collides(tx + facingX, ty + facingY, false);
        if(collidesFront) return false;
        switch(id) {
            case kick | fireBreath:
                return true;
            case slime:
                if(entityFront != null) return false;
            case gnome:
                if(entityFront != null) return false;
            case dragon:
                if(entityFront != null) return false;
            case sleep | levelUp:
                return true;
        }
        return mp >= cost;
    }

    public function chooseLevelUpPerk(isHP:Bool) {
        if(isHP) {
            hp += getLevelUpPerkHP();
        } else {
            atk += getLevelUpPerkAtk();
        }
        levelsPending--;
        level++;
        Game.inst.onChange();
    }
    public function getLevelUpPerkHP() {
        return PERK_MULT_HP * level;
    }
    public function getLevelUpPerkAtk() {
        return PERK_MULT_ATK * level;
    }

    public function set_controlled(v:Bool) {
        this.controlled = v;
        if(anim != null) {
            updateAnim();
        }
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
        var delay  = STEP_DURATION_WALK;
        switch(step) {
            case Move(dx, dy):
                Audio.playSound(Data.SoundKind.step);
                tx += dx;
                ty += dy;
                setFacing(dx, dy);
                onMoved();
            case TryMove(dx, dy, careful):
                tryMove(dx, dy, careful);
            case Hit(target):
                setFacing(Util.sign(target.tx - tx), Util.sign(target.ty - ty));
                hit(target, facingX, facingY);
                if(target.deleted) {
                    giveXP(target.xp);
                }
                delay = STEP_DURATION_HIT;
            case HitSummon(target):
                setFacing(Util.sign(target.tx - tx), Util.sign(target.ty - ty));
                hit(target, facingX, facingY);
                if(target.deleted) {
                    giveXP(target.totalXP);
                }
                delay = STEP_DURATION_HIT_SUMMON;
            case TakeHit(target):
                target.hit(this, -facingX, -facingY);
                delay = STEP_DURATION_HIT;
            case Open(door):
                if(Game.inst.inventory.spendKey(door.type)) {
                    door.open();
                }
        }
        updateVisual();
        Game.inst.onChange();
        if(queue.length == 0) {
            canTakeAction = true;
        }
        return delay;
    }

    public function get_ignoreSlippery() {
        return kind == slime;
    }
    override public function get_name() {
        return summon.name;
    }

    public function giveXP(amount:Int) {
        var playSound = false;
        totalXP += amount;
        xp += amount;
        while(xp >= getXPNeeded()) {
            xp -= getXPNeeded();
            levelsPending++;
            playSound = true;
        }
        xpPendingSOD.setParameters(3.5 / Math.pow(1. + levelsPending, .2), 1., 1);
        if(playSound) {
            Audio.playSound(Data.SoundKind.levelUp);
        }
    }

    public function getXPRemaining() {
        return getXPNeeded() - xp;
    }
    public function getXPNeeded() {
        return getXPNeededAt(level + levelsPending);
    }
    inline function getXPNeededAt(level:Int) {
        return level * 10;
    }
    public function getXPBetween(fromLevel:Int, count:Int) {
        var xp = 0;
        for(i in 0...count) {
            xp += (fromLevel + i) * 10;
        }
        return xp;
    }

    public function getDisplayXP() {
        var levels = 0;
        var rem = Math.round(xpPendingSOD.pos * 1000) / 1000;
        while(rem >= getXPNeededAt(level + levels)) {
            rem -= getXPNeededAt(level + levels);
            levels++;
        }
        if(rem + .1 >= getXPNeededAt(level + levels)) {
            levels++;
            rem = 0;
        }
        var ans = {levelsPending: levels, ratio: rem / getXPNeededAt(level + levels)};
        return ans;
    }

    public function get_xpPending() {
        return getXPBetween(level, levelsPending) + xp;
    }

    inline public function getEntityFront() {
        return Game.inst.getEntity(tx + facingX, ty + facingY);
    }

    public function tryPickScroll(spell:Data.SpellKind) {
        if(this.kind != hero) return false;
        if(spells.length == 2) {
            spells.pop();
            spellUsedCount.pop();
        }
        spells.push(spell);
        spellUsedCount.push(0);
        return true;
    }

    public function tryForgetScroll() {
        if(this.kind != hero) return false;
        if(spells.length == 1) return false;
        spells.pop();
        spellUsedCount.pop();
        return true;
    }
}