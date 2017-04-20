import sys
from automation import TaskManager, CommandSequence

# Load the sites of sites we we wish to crawl into a list
# E.g. ['http://www.example.com', 'http://dataskydd.net']
sites = [line.rstrip('\n') for line in open('municipalities_final_urls.txt')]

manager_params, browser_params = TaskManager.load_default_params(1)

browser_params[0]['headless'] = True #Launch browser headless
browser_params[0]['http_instrument'] = True # Record HTTP Requests and Responses
browser_params[0]['cookie_instrument'] = True # Records both JS cookies and HTTP response cookies to javascript_cookies

manager_params['data_directory'] = './data/'
manager_params['log_directory'] = './data/'

manager = TaskManager.TaskManager(manager_params, browser_params)

for site in sites:
    command_sequence = CommandSequence.CommandSequence(site, reset=True)
    command_sequence.browse(num_links=5, sleep=10, timeout=360)
    command_sequence.dump_profile_cookies(120)
    manager.execute_command_sequence(command_sequence, index='**')

manager.close()
