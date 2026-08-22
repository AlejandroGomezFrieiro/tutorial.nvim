return {
	id = "my-first",
	title = "My first tutorial",
	steps = {
	  {
	    id = "hello",
	    title = "Say hi",
	    body = { "You are inside your own tutorial." },
	  },
	  {
	    id = "act",
	    title = "Do a thing",
	    body = { "Run :echo well hello there" },
	    completion = { "on_command:echo" },
	  },
	},
}
