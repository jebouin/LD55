package ui;

import hxd.Key;
import Controller.Action;
import h2d.Object;
import h2d.Flow;

class Menu extends Flow {
    public var lines : Array<MenuLine> = [];
    public var selectedId(default, set) : Int;
    var holdActions : HoldActions;
    var sod : SecondOrderDynamics;

    public function new(parent:Object) {
        super(parent);
        layout = Vertical;
        verticalSpacing = 2;
        sod = new SecondOrderDynamics(4., 1., 0, 0, Precise);
    }

    public function init() {
        selectedId = 0;
        holdActions = new HoldActions();
        holdActions.add(Action.moveDown, moveDown);
        holdActions.add(Action.moveUp, moveUp);
    }

    public function delete() {
        for(line in lines) {
            line.delete();
        }
    }

    public inline function addLine(name:String, onPressed:Void->Void, goesBack:Bool=false) {
        var line = new MenuLine(this, name, goesBack);
        line.onPressed = onPressed;
        lines.push(line);
        line.init();
        return line;
    }

    public function update(dt:Float) {
        for(line in lines) {
            line.update(dt, selectedId == lines.indexOf(line));
        }
        var controller = Main.inst.controller;
        holdActions.update(dt);
        var selectedLine = lines[selectedId];
        if(controller.isPressed(Action.menuEnter) || Key.isPressed(Key.ENTER)) {
            if(lines[selectedId].canPress()) {
                lines[selectedId].press();
            }
        }
    }
    
    public function moveDown() {
        var nextId = selectedId + 1;
        while(nextId < lines.length && !lines[nextId].selectable) {
            nextId++;
        }
        if(nextId >= lines.length) {
            return false;
        }
        selectedId = nextId;
        onSuccessfulMove();
        return true;
    }
    public function moveUp() {
        var nextId = selectedId - 1;
        while(nextId >= 0 && !lines[nextId].selectable) {
            nextId--;
        }
        if(nextId < 0) {
            return false;
        }
        selectedId = nextId;
        onSuccessfulMove();
        return true;
    }
    function onSuccessfulMove() {
    }
    
    public function getSelectedY() {
        var line = lines[selectedId];
        return y + line.y + line.outerHeight / 2;
    }

    public function set_selectedId(id:Int) {
        for(i in 0...lines.length) {
            lines[i].selected = i == id;
        }
        selectedId = id;
        return id;
    }
    
    public function onMouseOverLine(line:MenuLine) {
        var id = lines.indexOf(line);
        if(id != -1) {
            selectedId = id;
        }
    }
    public function onMouseOutLine(line:MenuLine) {

    }
}