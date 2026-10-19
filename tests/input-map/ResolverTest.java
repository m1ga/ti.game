import ti.game.engine.InputResolver;
import java.util.*;
public class ResolverTest {
 static void check(boolean ok) { if (!ok) throw new AssertionError(); }
 public static void main(String[] args) {
  List<String> events = new ArrayList<>();
  InputResolver r = new InputResolver((action,context,down)->events.add(action+":"+context+":"+down));
  check(!r.hasBindings("mouse"));
  Map<String,Object> actions = new LinkedHashMap<>();
  actions.put("fire", new Object[]{Map.of("device","keyboard","code","Space"), Map.of("device","mouse","button","left"),Map.of("device","gamepad","button","a")});
  r.setMap(Map.of("gameplay",actions)); check(r.hasBindings("mouse"));
  r.transition("keyboard","1","Space",true); r.transition("keyboard","1","Space",true);
  r.transition("mouse","1","left",true); r.transition("keyboard","1","Space",false);
  check(events.size()==1); r.transition("mouse","1","left",false); check(events.size()==2);
  r.transition("gamepad","1","a",true); r.transition("gamepad","2","a",true);
  r.releaseDevice("gamepad","1"); check(events.size()==3); r.releaseDevice("gamepad","2"); check(events.size()==4);
  r.transition("keyboard","1","Space",true); r.setContext(null); check(events.size()==6);
  check(!r.hasBindings("mouse")); r.setContext("gameplay"); r.transition("keyboard","1","Space",true); check(events.size()==6);
  r.transition("keyboard","1","Space",false); r.transition("keyboard","1","Space",true);check(events.size()==7);
  try {r.setMap(Map.of("gameplay",Map.of("fire",new Object[]{Map.of("device","mouse","button","bad")})));throw new AssertionError();}catch(IllegalArgumentException expected){}
  check(events.size()==7);r.setMap(Map.of("gameplay",actions));check(events.size()==8);
  r.transition("keyboard","1","Space",true);check(events.size()==8);
  r.transition("keyboard","1","Space",false);r.transition("keyboard","1","Space",true);r.releaseAll();check(events.size()==10);
  System.out.println("InputResolver: aggregation, repeat, devices, context, invalid map, replacement, release passed");
 }
}
