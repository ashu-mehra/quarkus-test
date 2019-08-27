package org.acme.quickstart;

import javax.ws.rs.GET;
import javax.ws.rs.Path;
import javax.ws.rs.QueryParam;
import javax.ws.rs.Produces;
import javax.enterprise.event.Observes;
import io.quarkus.runtime.StartupEvent;
import java.text.SimpleDateFormat;
import java.util.Date;

@Path("/")
public class GreetingEndpoint {

	private static final String template = "Hello, %s!";

	@GET
	@Path("/greeting")
	@Produces("application/json")
	public String greeting(@QueryParam("name") String name) {
		System.out.println("End=" + new SimpleDateFormat("HH:mm:ss.SSS").format(new Date(System.currentTimeMillis())));
		String suffix = name != null ? name : "World";
		return String.format(template, suffix);
	}

	void onStart(@Observes StartupEvent startup) {
		System.out.println(new SimpleDateFormat("HH:mm:ss.SSS").format(new Date()));
		System.out.println("Application started");
	}
}
