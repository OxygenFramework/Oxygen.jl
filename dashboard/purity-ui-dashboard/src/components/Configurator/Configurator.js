// Chakra Imports
import {
  Box,
  Button,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  Flex,
  Icon,
  Link,
  Switch,
  Text,
  Stack,
  FormControl,
  FormLabel,
  Select,
  useColorMode,
  useColorModeValue,
  useDisclosure
} from "@chakra-ui/react";
import GitHubButton from "react-github-btn";
import { Separator } from "components/Separator/Separator";
import PropTypes from "prop-types";
import React, { useState } from "react";
import { useHookstate } from '@hookstate/core';
import { globalState } from "../../state/index.ts";

export default function Configurator(props) {

  const state = useHookstate(globalState);

  const { secondary, isOpen, onClose, fixed, ...rest } = props;
  const [switched, setSwitched] = useState(props.isChecked);

  const pollingSettings = useDisclosure({defaultIsOpen: true});

  const { colorMode, toggleColorMode } = useColorMode();

  // Chakra Color Mode
  let fixedDisplay = "flex";
  if (props.secondary) {
    fixedDisplay = "none";
  }

  let bgButton = useColorModeValue(
    "linear-gradient(81.62deg, #313860 2.25%, #151928 79.87%)",
    "white"
  );
  let colorButton = useColorModeValue("white", "gray.700");
  const secondaryButtonBg = useColorModeValue("white", "transparent");
  const secondaryButtonBorder = useColorModeValue("gray.700", "white");
  const secondaryButtonColor = useColorModeValue("gray.700", "white");
  const settingsRef = React.useRef();

  const isPollingOn = state.settings.poll.get();

  function togglePolling(){
    state.settings.poll.set(prev => !prev);
  }

  return (
    <>
      <Drawer
        isOpen={props.isOpen}
        onClose={props.onClose}
        placement={document.documentElement.dir === "rtl" ? "left" : "right"}
        finalFocusRef={settingsRef}
        blockScrollOnMount={false}
      >
        <DrawerContent>
          <DrawerHeader pt="24px" px="24px">
            <DrawerCloseButton />
            <Text fontSize="xl" fontWeight="bold" mt="16px">
              Oxygen Metrics Settings
            </Text>
            <Text fontSize="md" mb="16px">
              See your dashboard options.
            </Text>
            <Separator />
          </DrawerHeader>
          <DrawerBody w="340px" ps="24px" pe="40px">
            <Flex flexDirection="column">

              <Box display={fixedDisplay} justifyContent="space-between">
                <Text fontSize="md" fontWeight="600" mb="4px">
                    Poll Server
                </Text>
                <Switch isChecked={isPollingOn} onChange={togglePolling} />
              </Box>

              <Box display={fixedDisplay} justifyContent="space-between" mt={3}>
                <Text fontSize="md" fontWeight="600" mb="4px">
                  Interval
                </Text>
                <Select id='poll-interval'
                  onChange={(e) => state.settings.interval.set(parseInt(e.target.value))}
                  value={state.settings.interval.get()} 
                  size='md' width={140} 
                  >
                  <option value={3}>3 Seconds</option>
                  <option value={1}>1 Second</option>
                  <option value={5}>5 Seconds</option>
                  <option value={10}>10 Seconds</option>
                  <option value={30}>30 Seconds</option>
                  <option value={60}>60 Seconds</option>
                </Select>
              </Box>

              <Separator mt="5" mb="5"/>

              <Box>
                <Text fontSize="md" fontWeight="600">
                  Sidenav Type
                </Text>
                <Text fontSize="sm" mb="16px">
                  Choose between 2 different sidenav types.
                </Text>
                <Flex>
                  <Button
                    w="50%"
                    p="8px 32px"
                    me="8px"
                    colorScheme="teal"
                    borderColor="blue.700"
                    color="blue.700"
                    variant="outline"
                    fontSize="xs"
                    onClick={props.onTransparent}
                  >
                    Transparent
                  </Button>
                  <Button
                    type="submit"
                    bg="blue.700"
                    w="50%"
                    p="8px 32px"
                    mb={5}
                    _hover="blue.700"
                    color="white"
                    fontSize="xs"
                    onClick={props.onOpaque}
                  >
                    Opaque
                  </Button>
                </Flex>
              </Box>
              <Box
                display={fixedDisplay}
                justifyContent="space-between "
                mb="16px"
              >
                <Text fontSize="md" fontWeight="600" mb="4px">
                  Navbar Fixed
                </Text>
                <Switch
                  colorScheme="teal"
                  isChecked={switched}
                  onChange={(event) => {
                    if (switched === true) {
                      props.onSwitch(false);
                      setSwitched(false);
                    } else {
                      props.onSwitch(true);
                      setSwitched(true);
                    }
                  }}
                />
              </Box>
              <Flex
                justifyContent="space-between"
                alignItems="center"
                mb="24px"
              >
                <Text fontSize="md" fontWeight="600" mb="4px">
                  Dark/Light
                </Text>
                <Button onClick={toggleColorMode}>
                  Toggle {colorMode === "light" ? "Dark" : "Light"}
                </Button>
              </Flex>

              <Separator />
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </>
  );
}
Configurator.propTypes = {
  secondary: PropTypes.bool,
  isOpen: PropTypes.bool,
  onClose: PropTypes.func,
  fixed: PropTypes.bool,
};
