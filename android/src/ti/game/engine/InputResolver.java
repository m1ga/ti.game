package ti.game.engine;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * Maps physical digital inputs (keyboard keys, mouse buttons, gamepad
 * buttons) onto named actions per context. Digital edges only — independent
 * of the renderer and of Kroll. All public methods are synchronized: the JS
 * thread writes the map and context, the UI thread feeds edges.
 */
public final class InputResolver
{
	public interface Listener
	{
		void action(String action, String context, boolean down);
	}

	private static final Set<String> PAD = new HashSet<>(Arrays.asList(
		"a", "b", "x", "y", "l1", "r1", "l2", "r2", "l3", "r3",
		"start", "select", "home", "up", "down", "left", "right"));
	private static final List<String> MOUSE = Arrays.asList("left", "middle", "right");

	private final Listener listener;
	// context -> action -> bindings ("device:code")
	private Map<String, Map<String, Set<String>>> map = new LinkedHashMap<>();
	private String context = "gameplay";
	// physical source ("device:id:code") -> binding ("device:code")
	private final Map<String, String> held = new LinkedHashMap<>();
	// action -> physical sources currently holding it down
	private final Map<String, Set<String>> active = new LinkedHashMap<>();

	public InputResolver(Listener listener)
	{
		this.listener = listener;
	}

	private static IllegalArgumentException invalid()
	{
		return new IllegalArgumentException("Invalid inputMap: expected contexts, actions and digital bindings");
	}

	public static boolean validCode(String code)
	{
		return code.matches("Key[A-Z]|Digit[0-9]|F([1-9]|1[0-2])|Arrow(Up|Down|Left|Right)"
			+ "|Space|Escape|Enter|Tab|Backspace|Delete|Home|End|PageUp|PageDown"
			+ "|Shift(Left|Right)|Control(Left|Right)|Alt(Left|Right)|Meta(Left|Right)");
	}

	private static boolean validBinding(Object device, String code)
	{
		if ("keyboard".equals(device)) {
			return validCode(code);
		}
		if ("mouse".equals(device)) {
			return MOUSE.contains(code);
		}
		if ("gamepad".equals(device)) {
			return PAD.contains(code);
		}
		return false;
	}

	public synchronized void setMap(Object value)
	{
		if (!(value instanceof Map)) {
			throw invalid();
		}
		Map<String, Map<String, Set<String>>> next = new LinkedHashMap<>();
		for (Map.Entry<?, ?> ctx : ((Map<?, ?>) value).entrySet()) {
			if (!(ctx.getKey() instanceof String) || ((String) ctx.getKey()).isEmpty()
				|| !(ctx.getValue() instanceof Map)) {
				throw invalid();
			}
			Map<String, Set<String>> actions = new LinkedHashMap<>();
			for (Map.Entry<?, ?> entry : ((Map<?, ?>) ctx.getValue()).entrySet()) {
				if (!(entry.getKey() instanceof String) || ((String) entry.getKey()).isEmpty()) {
					throw invalid();
				}
				Object list = entry.getValue();
				Iterable<?> bindings;
				if (list instanceof Object[]) {
					bindings = Arrays.asList((Object[]) list);
				} else if (list instanceof List) {
					bindings = (List<?>) list;
				} else {
					throw invalid();
				}
				Set<String> keys = new LinkedHashSet<>();
				for (Object binding : bindings) {
					if (!(binding instanceof Map)) {
						throw invalid();
					}
					Map<?, ?> b = (Map<?, ?>) binding;
					Object device = b.get("device");
					boolean keyboard = "keyboard".equals(device);
					Object code = b.get(keyboard ? "code" : "button");
					if (b.size() != 2 || !(code instanceof String) || !validBinding(device, (String) code)) {
						throw invalid();
					}
					keys.add(device + ":" + code);
				}
				actions.put((String) entry.getKey(), keys);
			}
			next.put((String) ctx.getKey(), actions);
		}
		releaseActions();
		map = next; // held physical sources stay latched until an up edge
	}

	public synchronized Object getMap()
	{
		Map<String, Object> result = new LinkedHashMap<>();
		for (Map.Entry<String, Map<String, Set<String>>> ctx : map.entrySet()) {
			Map<String, Object> actions = new LinkedHashMap<>();
			for (Map.Entry<String, Set<String>> action : ctx.getValue().entrySet()) {
				List<Object> bindings = new ArrayList<>();
				for (String key : action.getValue()) {
					int sep = key.indexOf(':');
					String device = key.substring(0, sep);
					Map<String, Object> binding = new LinkedHashMap<>();
					binding.put("device", device);
					binding.put(device.equals("keyboard") ? "code" : "button", key.substring(sep + 1));
					bindings.add(binding);
				}
				actions.put(action.getKey(), bindings.toArray());
			}
			result.put(ctx.getKey(), actions);
		}
		return result;
	}

	/** True when the active context binds at least one control of this device. */
	public synchronized boolean hasBindings(String device)
	{
		Map<String, Set<String>> actions = map.get(context);
		if (actions == null) {
			return false;
		}
		String prefix = device + ":";
		for (Set<String> bindings : actions.values()) {
			for (String binding : bindings) {
				if (binding.startsWith(prefix)) {
					return true;
				}
			}
		}
		return false;
	}

	public synchronized String getContext()
	{
		return context;
	}

	public synchronized void setContext(String value)
	{
		if (Objects.equals(context, value)) {
			return;
		}
		releaseActions();
		context = value;
	}

	/** Reports every active action as released (in the current context). */
	private void releaseActions()
	{
		List<String> old = new ArrayList<>(active.keySet());
		active.clear();
		for (String action : old) {
			listener.action(action, context, false);
		}
	}

	/**
	 * Feeds one physical edge. @return false when it was not an edge (the
	 * source was already down, or up without a matching down).
	 */
	public synchronized boolean transition(String device, String id, String code, boolean down)
	{
		String source = device + ":" + id + ":" + code;
		if (down) {
			if (held.containsKey(source)) {
				return false;
			}
			String binding = device + ":" + code;
			held.put(source, binding);
			Map<String, Set<String>> actions = map.get(context);
			if (actions == null) {
				return true;
			}
			for (Map.Entry<String, Set<String>> action : actions.entrySet()) {
				if (!action.getValue().contains(binding)) {
					continue;
				}
				Set<String> sources = active.get(action.getKey());
				boolean first = sources == null;
				if (first) {
					sources = new LinkedHashSet<>();
					active.put(action.getKey(), sources);
				}
				sources.add(source);
				if (first) {
					listener.action(action.getKey(), context, true);
				}
			}
		} else {
			if (held.remove(source) == null) {
				return false;
			}
			for (String action : new ArrayList<>(active.keySet())) {
				Set<String> sources = active.get(action);
				if (sources.remove(source) && sources.isEmpty()) {
					active.remove(action);
					listener.action(action, context, false);
				}
			}
		}
		return true;
	}

	/** Releases every control held on one physical device. */
	public synchronized void releaseDevice(String device, String id)
	{
		String prefix = device + ":" + id + ":";
		for (String source : new ArrayList<>(held.keySet())) {
			if (source.startsWith(prefix)) {
				String code = held.get(source).substring(device.length() + 1);
				transition(device, id, code, false);
			}
		}
	}

	public synchronized void releaseAll()
	{
		releaseActions();
		held.clear();
	}
}
